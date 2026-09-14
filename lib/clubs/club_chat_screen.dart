import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../moderation/text_filter.dart';
import '../utils/dedupe_stream_rows.dart';

class ClubChatScreen extends StatefulWidget {
  final String clubId;
  final String clubName;

  const ClubChatScreen({
    super.key,
    required this.clubId,
    required this.clubName,
  });

  @override
  State<ClubChatScreen> createState() => _ClubChatScreenState();
}

class _ClubChatScreenState extends State<ClubChatScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _sending = false;
  String? _uid;

  @override
  void initState() {
    super.initState();
    // No "ensure parent doc exists" step needed -- club_messages.club_id
    // is a plain foreign key, not a Firestore-style parent document that
    // had to exist before its subcollection was reachable (see
    // docs/supabase-schema.md's note on why that entire outage class,
    // Phase 18 of the Firebase hardening work, can't recur here).
    _uid = Supabase.instance.client.auth.currentUser?.id;
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending || _uid == null) return;

    final filterResult = TextFilter.filter(text);
    if (!filterResult.isAllowed) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠️ Message blocked by filter')),
        );
      }
      return;
    }

    setState(() => _sending = true);
    _controller.clear();

    try {
      await Supabase.instance.client.from('club_messages').insert({
        'club_id': widget.clubId,
        'user_id': _uid,
        'text': filterResult.cleanedText,
      });
    } catch (e) {
      debugPrint('Club chat send failed: $e');
      if (mounted) {
        // Restore the text -- it was cleared above for a snappy send-feel,
        // so a failure must not leave the user re-typing a message that
        // just silently vanished (this had no catch block at all before,
        // so _sending also stayed stuck true forever on any failure,
        // permanently disabling the send button for the rest of the
        // screen's lifetime).
        _controller.text = text;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message not sent. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_uid == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(widget.clubName),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: Supabase.instance.client
                  .from('club_messages')
                  .stream(primaryKey: ['id'])
                  .eq('club_id', widget.clubId)
                  .order('created_at', ascending: false)
                  .limit(100),
              builder: (context, snap) {
                if (snap.hasError) {
                  return const Center(
                    child: Text(
                      'Failed to load messages',
                      style: TextStyle(color: Colors.white54),
                    ),
                  );
                }

                if (!snap.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                final docs = dedupeStreamRowsById(snap.data!);

                if (docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'No messages yet',
                      style: TextStyle(color: Colors.white54),
                    ),
                  );
                }

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final data = docs[i];
                    final isMe = data['user_id'] == _uid;

                    return Align(
                      alignment:
                          isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isMe
                              ? Colors.deepPurple
                              : Colors.white.withAlpha(20),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          data['text'] ?? '',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              color: const Color(0xFF1C1C1E),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Message club…',
                        hintStyle: TextStyle(color: Colors.white54),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _sending ? Icons.hourglass_top : Icons.send,
                      color: Colors.deepPurple,
                    ),
                    onPressed: _send,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
