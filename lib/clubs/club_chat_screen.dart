import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../moderation/text_filter.dart';
import '../utils/dedupe_stream_rows.dart';
import '../core/app_colors.dart';
import '../core/haptics.dart';
import '../core/spacing.dart';
import '../core/widgets/chat_bubble.dart';
import '../core/widgets/empty_state.dart';
import '../core/widgets/entrance.dart';

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
          const SnackBar(content: Text('Message blocked by filter')),
        );
      }
      return;
    }

    setState(() => _sending = true);
    _controller.clear();
    AppHaptics.tap();

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
      appBar: AppBar(title: Text(widget.clubName)),
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
                  return const EmptyState(
                    icon: Icons.error_outline_rounded,
                    title: "Couldn't load messages",
                    isError: true,
                  );
                }

                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = dedupeStreamRowsById(snap.data!);

                if (docs.isEmpty) {
                  return const EmptyState(
                    icon: Icons.forum_outlined,
                    title: 'No messages yet',
                    message: 'Start the conversation.',
                  );
                }

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(AppSpace.md),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final data = docs[i];
                    final isMe = data['user_id'] == _uid;
                    final showTail = i == 0 || docs[i - 1]['user_id'] != data['user_id'];

                    return Entrance(
                      key: ValueKey(data['id']),
                      offset: const Offset(0, 0.15),
                      duration: const Duration(milliseconds: 180),
                      child: ChatBubble(
                        text: data['text'] ?? '',
                        isMe: isMe,
                        showTail: showTail,
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textCapitalization: TextCapitalization.sentences,
                      minLines: 1,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        hintText: 'Message club…',
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Material(
                      color: AppColors.accent,
                      shape: const CircleBorder(),
                      child: InkWell(
                        onTap: _sending ? null : _send,
                        customBorder: const CircleBorder(),
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: _sending
                              ? const Padding(
                                  padding: EdgeInsets.all(13),
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 20),
                        ),
                      ),
                    ),
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
