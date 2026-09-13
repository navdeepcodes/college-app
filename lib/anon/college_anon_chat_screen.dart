import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart'; // Added for haptics
import '../moderation/text_filter.dart';

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
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (!mounted) return;

    setState(() {
      _anonId = snap.data()?['anonId'];
    });
  }

  /// The canonical college slug embedded in the room id (`college_<collegeId>`).
  /// Sent with every message so the Firestore rule can verify
  /// `collegeId == users/{uid}.collegeId`.
  String get _roomCollegeId {
    const prefix = 'college_';
    return widget.chatId.startsWith(prefix)
        ? widget.chatId.substring(prefix.length)
        : '';
  }

  Future<void> _sendMessage() async {
    final user = FirebaseAuth.instance.currentUser;
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

    // Real 10s client-side cooldown between sends.
    final lastSent = _lastSent;
    if (lastSent != null) {
      final elapsed =
          DateTime.now().difference(lastSent).inMilliseconds;
      if (elapsed < 10000) {
        final remaining = (10000 - elapsed) ~/ 1000 + 1;
        _showError('Slow down! $remaining s before sending again.');
        return;
      }
    }

    // Add haptic feedback for a premium feel
    HapticFeedback.lightImpact();

    setState(() => _sending = true);
    final textToUpload = result.cleanedText;
    _msgController.clear();

    try {
      final batch = FirebaseFirestore.instance.batch();
      final msgRef = FirebaseFirestore.instance
          .collection('anon_chats')
          .doc(widget.chatId)
          .collection('messages')
          .doc();

      final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);

      batch.set(msgRef, {
        'anonId': _anonId,
        'text': textToUpload,
        'userId': user.uid,
        'collegeId': roomCollegeId,
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(seconds: 90))),
      });

      batch.update(userRef, {
        'lastAnonMessage': FieldValue.serverTimestamp(),
      });

      await batch.commit();
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
        body: Center(child: CircularProgressIndicator(color: Colors.deepPurpleAccent)),
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
              style: TextStyle(fontSize: 11, color: Colors.redAccent, fontWeight: FontWeight.w600),
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
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('anon_chats')
                    .doc(widget.chatId)
                    .collection('messages')
                    .orderBy('createdAt', descending: true)
                    .limit(50)
                    .snapshots(),
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
                        color: Colors.deepPurpleAccent,
                      ),
                    );
                  }

                  final now = DateTime.now();
                  final docs = snapshot.data!.docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    if (!data.containsKey('expiresAt')) return false;
                    final expiresAt = (data['expiresAt'] as Timestamp).toDate();
                    return expiresAt.isAfter(now);
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
                      final data = docs[i].data() as Map<String, dynamic>;
                      final expiresAt = (data['expiresAt'] as Timestamp).toDate();
                      final remaining = expiresAt.difference(now).inSeconds;

                      return _MessageBubble(
                        anonId: data['anonId'] ?? 'ANON',
                        text: data['text'] ?? '',
                        remaining: remaining > 0 ? remaining : 0,
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
                  colors: [Colors.deepPurpleAccent, Color(0xFF6200EA)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.deepPurpleAccent.withValues(alpha: 0.4),
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
                      color: Colors.deepPurpleAccent,
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