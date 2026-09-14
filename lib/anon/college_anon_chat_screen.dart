import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../moderation/text_filter.dart';
import '../core/app_colors.dart';
import '../core/haptics.dart';
import '../core/widgets/entrance.dart';

class CollegeAnonChatScreen extends StatefulWidget {
  final String chatId;
  final String chatName;

  const CollegeAnonChatScreen({
    super.key,
    required this.chatId,
    required this.chatName,
  });

  @override
  State<CollegeAnonChatScreen> createState() => _CollegeAnonChatScreenState();
}

class _CollegeAnonChatScreenState extends State<CollegeAnonChatScreen> {
  final TextEditingController _msgController = TextEditingController();
  bool _sending = false;
  String? _anonId;
  DateTime? _lastSent;

  SupabaseClient get _db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadContext();
  }

  @override
  void dispose() {
    _msgController.dispose();
    super.dispose();
  }

  Future<void> _loadContext() async {
    final user = _db.auth.currentUser;
    if (user == null) return;

    final rows = await _db.from('profiles').select().eq('id', user.id).limit(1);

    if (!mounted) return;

    setState(() {
      _anonId = rows.isNotEmpty ? rows.first['anon_id'] : null;
    });

    // Ensure the room exists (idempotent — see supabase-security-model.md,
    // anon_rooms is a fixed-id-per-college row anyone at that college may
    // create-if-missing). Firestore's version did this implicitly by
    // treating a get() failure as "not created yet"; here it's a plain
    // select-then-insert against a row that reads back empty, not an
    // error, when absent.
    final roomCollegeId = _roomCollegeId;
    if (roomCollegeId.isNotEmpty) {
      final existing = await _db
          .from('anon_rooms')
          .select('college_id')
          .eq('college_id', roomCollegeId)
          .limit(1);
      if (existing.isEmpty) {
        try {
          await _db.from('anon_rooms').insert({
            'college_id': roomCollegeId,
            'created_by': user.id,
          });
        } catch (_) {
          // Lost a create race to another student at the same college —
          // the room exists either way now.
        }
      }
    }
  }

  /// The canonical college slug embedded in the room id (`college_<collegeId>`).
  String get _roomCollegeId {
    const prefix = 'college_';
    return widget.chatId.startsWith(prefix)
        ? widget.chatId.substring(prefix.length)
        : '';
  }

  Future<void> _sendMessage() async {
    final user = _db.auth.currentUser;
    final rawText = _msgController.text.trim();
    final roomCollegeId = _roomCollegeId;

    if (rawText.isEmpty || roomCollegeId.isEmpty ||
        _anonId == null || _sending || user == null) {
      return;
    }

    final result = TextFilter.filter(rawText);
    if (!result.isAllowed) {
      _showError('⚠️ Message blocked by filter');
      return;
    }

    final lastSent = _lastSent;
    if (lastSent != null) {
      final elapsed = DateTime.now().difference(lastSent).inMilliseconds;
      if (elapsed < 10000) {
        final remaining = (10000 - elapsed) ~/ 1000 + 1;
        _showError('Slow down! $remaining s before sending again.');
        return;
      }
    }

    AppHaptics.tap();

    setState(() => _sending = true);
    final textToUpload = result.cleanedText;
    _msgController.clear();

    try {
      // .toUtc() is load-bearing, not cosmetic: anon_messages_insert's RLS
      // (supabase/migrations/20260914000002_rls_policies.sql) requires
      // expires_at within [now()-120s, now()+900s] of the *server's* UTC
      // clock. DateTime.now() is local device time; toIso8601String() on
      // a non-UTC DateTime omits the offset entirely, so Postgres reads
      // it as if it already were UTC. Found live, on-device, on an
      // Asia/Kolkata (UTC+5:30) emulator -- exactly the timezone every
      // real user of this app (NMIT/RVCE/BMS/PES are all Bangalore) will
      // actually be in: every send failed with a generic "Message not
      // sent," the +5:30 skew blowing straight through the +900s upper
      // bound, RLS silently rejecting the insert.
      await _db.from('anon_messages').insert({
        'room_college_id': roomCollegeId,
        'anon_id': _anonId,
        'text': textToUpload,
        'user_id': user.id,
        'expires_at': DateTime.now()
            .toUtc()
            .add(const Duration(seconds: 90))
            .toIso8601String(),
      });

      _lastSent = DateTime.now();
    } catch (e) {
      _showError('Message not sent. Try again.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_anonId == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: AppColors.anonAccent)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.7),
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 0.5)),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.chatName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const Text(
              'Disappearing in 90s',
              style: TextStyle(fontSize: 11, color: AppColors.danger, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topLeft,
            radius: 1.5,
            colors: [Color(0xFF1A1A2E), Colors.black],
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: _db
                    .from('anon_messages')
                    .stream(primaryKey: ['id'])
                    .eq('room_college_id', _roomCollegeId)
                    .order('created_at', ascending: false)
                    .limit(50),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Center(
                      child: Text(
                        'Failed to load messages',
                        style: TextStyle(color: Colors.white38),
                      ),
                    );
                  }

                  if (!snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.anonAccent,
                      ),
                    );
                  }

                  final now = DateTime.now();
                  // Dedupe by id: found live, on-device, a freshly-sent
                  // message rendering twice even though only one row
                  // exists in the database (confirmed directly) -- the
                  // underlying .stream() can emit the same row from both
                  // its initial fetch and the realtime INSERT event for
                  // it before its own internal cache reconciles by
                  // primary key, and that transient duplicate didn't
                  // self-correct on the next snapshot either. Collapsing
                  // by id here is correct regardless of which layer
                  // produces the duplicate.
                  final seen = <Object?>{};
                  final docs = snapshot.data!.where((data) {
                    final expiresRaw = data['expires_at'] as String?;
                    if (expiresRaw == null) return false;
                    final expiresAt = DateTime.tryParse(expiresRaw);
                    if (expiresAt == null || !expiresAt.isAfter(now)) return false;
                    return seen.add(data['id']);
                  }).toList();

                  if (docs.isEmpty) {
                    return const Center(
                      child: Text('Say the first thing 👀', style: TextStyle(color: Colors.white38, letterSpacing: 1.2)),
                    );
                  }

                  return ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(20, 100, 20, 20),
                    itemCount: docs.length,
                    itemBuilder: (_, i) {
                      final data = docs[i];
                      final expiresAt = DateTime.parse(data['expires_at'] as String);
                      final remaining = expiresAt.difference(now).inSeconds;

                      return Entrance(
                        key: ValueKey(data['id']),
                        offset: const Offset(0, 0.15),
                        duration: const Duration(milliseconds: 180),
                        child: _MessageBubble(
                          anonId: data['anon_id'] ?? 'ANON',
                          text: data['text'] ?? '',
                          remaining: remaining > 0 ? remaining : 0,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            _buildInputArea(),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.of(context).padding.bottom + 10,
          top: 10
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.8),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E),
                borderRadius: BorderRadius.circular(25),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: TextField(
                controller: _msgController,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                maxLines: 4,
                minLines: 1,
                decoration: const InputDecoration(
                  hintText: 'Share a secret...',
                  hintStyle: TextStyle(color: Colors.white30),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _sendMessage,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 48,
              width: 48,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.anonAccent, AppColors.accentDeep],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.anonAccent.withValues(alpha: 0.4),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: Icon(
                _sending ? Icons.hourglass_top_rounded : Icons.arrow_upward_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final String anonId;
  final String text;
  final int remaining;

  const _MessageBubble({required this.anonId, required this.text, required this.remaining});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomRight: Radius.circular(20),
            bottomLeft: Radius.circular(4),
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.02),
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    anonId.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10,
                      letterSpacing: 1.2,
                      color: AppColors.anonAccent,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Icon(Icons.timer_outlined, size: 10, color: Colors.white30),
                  const SizedBox(width: 4),
                  Text(
                    '${remaining}s',
                    style: const TextStyle(fontSize: 10, color: Colors.white30, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 15,
                  color: Color(0xFFE1E1E1),
                  height: 1.4,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
