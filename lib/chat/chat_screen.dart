import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../moderation/text_filter.dart';
import '../utils/dedupe_stream_rows.dart';
import '../core/app_colors.dart';
import '../core/haptics.dart';
import '../core/spacing.dart';
import '../core/widgets/avatar.dart';
import '../core/widgets/chat_bubble.dart';
import '../core/widgets/entrance.dart';

class ChatScreen extends StatefulWidget {
  final String peerUid;

  const ChatScreen({
    super.key,
    required this.peerUid,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final String _currentUid = Supabase.instance.client.auth.currentUser!.id;
  String? _conversationId;
  late final Future<void> _ready;
  bool _sending = false;

  SupabaseClient get _db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _ready = _ensureConversationExists().then((_) => _markDelivered());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<String> get _sortedPair => [_currentUid, widget.peerUid]..sort();

  Future<void> _ensureConversationExists() async {
    final pair = _sortedPair;

    // A missing conversation reads back as an empty list, not an error --
    // no try/catch workaround needed here, unlike the Firestore version
    // (see docs/supabase-schema.md).
    final existing = await _db
        .from('conversations')
        .select('id')
        .eq('user_a', pair[0])
        .eq('user_b', pair[1])
        .limit(1);

    if (existing.isNotEmpty) {
      _conversationId = existing.first['id'] as String;
      return;
    }

    try {
      final inserted = await _db
          .from('conversations')
          .insert({'user_a': pair[0], 'user_b': pair[1]})
          .select('id')
          .single();
      _conversationId = inserted['id'] as String;
    } catch (_) {
      // Lost a create race to the peer opening this same conversation at
      // the same moment (UNIQUE(user_a, user_b) rejects the second
      // insert) -- the row now exists either way, so fetch it.
      final retry = await _db
          .from('conversations')
          .select('id')
          .eq('user_a', pair[0])
          .eq('user_b', pair[1])
          .limit(1);
      if (retry.isNotEmpty) {
        _conversationId = retry.first['id'] as String;
      }
    }
  }

  Future<void> _markDelivered() async {
    if (_conversationId == null) return;
    await _db
        .from('messages')
        .update({'status': 'delivered'})
        .eq('conversation_id', _conversationId!)
        .eq('to_uid', _currentUid)
        .eq('status', 'sent');
  }

  Future<void> _markSeen() async {
    if (_conversationId == null) return;
    await _db
        .from('messages')
        .update({'status': 'seen'})
        .eq('conversation_id', _conversationId!)
        .eq('to_uid', _currentUid)
        .eq('status', 'delivered');
  }

  Future<void> _sendMessage() async {
    if (_sending) return;
    final text = _controller.text.trim();
    if (text.isEmpty || _conversationId == null) return;

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
      await _db.from('messages').insert({
        'conversation_id': _conversationId,
        'from_uid': _currentUid,
        'to_uid': widget.peerUid,
        'text': filterResult.cleanedText,
        'status': 'sent',
      });
      // conversations.last_message/last_message_at is trigger-maintained
      // (bump_conversation_last_message) -- no follow-up update needed.
    } catch (e) {
      debugPrint('Chat send failed: $e');
      if (mounted) {
        // Restore the text rather than silently losing it -- the controller
        // was already cleared above for a snappy send-feel, so a failure
        // must not leave the user re-typing a message that just vanished.
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
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: StreamBuilder<List<Map<String, dynamic>>>(
          stream: _db
              .from('profiles')
              .stream(primaryKey: ['id'])
              .eq('id', widget.peerUid)
              .limit(1),
          builder: (_, snap) {
            if (!snap.hasData || snap.data!.isEmpty) return const SizedBox();
            final u = snap.data!.first;
            final name = u['name'] ?? '';

            return Row(
              children: [
                AppAvatar(photoUrl: u['photo_url'], name: name, radius: 16),
                const SizedBox(width: 10),
                Flexible(child: Text(name, overflow: TextOverflow.ellipsis)),
              ],
            );
          },
        ),
      ),
      body: FutureBuilder<void>(
        future: _ready,
        builder: (context, readySnap) {
          if (readySnap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          return _buildChatBody(context);
        },
      ),
    );
  }

  Widget _buildChatBody(BuildContext context) {
    final conversationId = _conversationId;
    if (conversationId == null) {
      // _ensureConversationExists() can complete without throwing yet still
      // leave _conversationId null (its own catch block assumes any insert
      // failure was a create-race and retries the same SELECT -- if the
      // real cause was something else, e.g. a network failure, that retry
      // comes back empty too). Surfacing that as a clear message here beats
      // the null-assertion below crashing this screen's build.
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            "Couldn't open this conversation. Go back and try again.",
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: _db
                .from('messages')
                .stream(primaryKey: ['id'])
                .eq('conversation_id', conversationId)
                .order('created_at', ascending: false)
                .limit(50),
            builder: (_, snap) {
              if (snap.hasError) {
                return const Center(
                  child: Text('Failed to load messages'),
                );
              }

              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final msgs = dedupeStreamRowsById(snap.data!);

              final hasUnseen = msgs.any((d) =>
                  d['to_uid'] == _currentUid && d['status'] == 'delivered');
              if (hasUnseen) {
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => _markSeen());
              }

              if (msgs.isEmpty) {
                return const Center(child: Text('Say hi 👋'));
              }

              return ListView.builder(
                reverse: true,
                padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.sm),
                itemCount: msgs.length,
                itemBuilder: (_, i) {
                  final d = msgs[i];
                  final isMe = d['from_uid'] == _currentUid;
                  // Newer neighbor is msgs[i - 1] since the list is
                  // reversed (index 0 = most recent). A tail (tight
                  // corner) belongs on the newest bubble of a
                  // consecutive same-sender run.
                  final showTail = i == 0 || msgs[i - 1]['from_uid'] != d['from_uid'];

                  return Entrance(
                    key: ValueKey(d['id']),
                    offset: const Offset(0, 0.15),
                    duration: const Duration(milliseconds: 180),
                    child: ChatBubble(
                      text: d['text'] ?? '',
                      isMe: isMe,
                      showTail: showTail,
                      footer: isMe && showTail
                          ? MessageStatusIcon(status: d['status'] ?? 'sent')
                          : null,
                    ),
                  );
                },
              );
            },
          ),
        ),
        _InputBar(
          onSend: _sending ? null : _sendMessage,
          controller: _controller,
        ),
      ],
    );
  }
}

class _InputBar extends StatelessWidget {
  final VoidCallback? onSend;
  final TextEditingController controller;

  const _InputBar({required this.onSend, required this.controller});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
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
                controller: controller,
                textCapitalization: TextCapitalization.sentences,
                minLines: 1,
                maxLines: 5,
                decoration: const InputDecoration(
                  hintText: 'Message...',
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: onSend == null
                    ? Container(
                        key: const ValueKey('busy'),
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        child: const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : Material(
                        key: const ValueKey('ready'),
                        color: AppColors.accent,
                        shape: const CircleBorder(),
                        child: InkWell(
                          onTap: onSend,
                          customBorder: const CircleBorder(),
                          child: const SizedBox(
                            width: 44,
                            height: 44,
                            child: Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 20),
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
