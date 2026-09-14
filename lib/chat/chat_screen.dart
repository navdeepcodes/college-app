import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../moderation/text_filter.dart';

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
    final text = _controller.text.trim();
    if (text.isEmpty || _conversationId == null) return;

    final filterResult = TextFilter.filter(text);
    if (!filterResult.isAllowed) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠️ Message blocked by filter')),
        );
      }
      return;
    }

    _controller.clear();

    await _db.from('messages').insert({
      'conversation_id': _conversationId,
      'from_uid': _currentUid,
      'to_uid': widget.peerUid,
      'text': filterResult.cleanedText,
      'status': 'sent',
    });
    // conversations.last_message/last_message_at is trigger-maintained
    // (bump_conversation_last_message) -- no follow-up update needed.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: StreamBuilder<List<Map<String, dynamic>>>(
          stream: _db
              .from('profiles')
              .stream(primaryKey: ['id'])
              .eq('id', widget.peerUid)
              .limit(1),
          builder: (_, snap) {
            if (!snap.hasData || snap.data!.isEmpty) return const SizedBox();
            final u = snap.data!.first;

            return Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundImage:
                      u['photo_url'] != null ? NetworkImage(u['photo_url']) : null,
                  child: u['photo_url'] == null
                      ? const Icon(Icons.person, size: 16)
                      : null,
                ),
                const SizedBox(width: 8),
                Text(u['name'] ?? ''),
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
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: _db
                .from('messages')
                .stream(primaryKey: ['id'])
                .eq('conversation_id', _conversationId!)
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

              final msgs = snap.data!;

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
                itemCount: msgs.length,
                itemBuilder: (_, i) {
                  final d = msgs[i];
                  final isMe = d['from_uid'] == _currentUid;

                  return _ChatBubble(
                    text: d['text'],
                    isMe: isMe,
                    status: d['status'],
                  );
                },
              );
            },
          ),
        ),
        _InputBar(onSend: _sendMessage, controller: _controller),
      ],
    );
  }
}

class _InputBar extends StatelessWidget {
  final VoidCallback onSend;
  final TextEditingController controller;

  const _InputBar({required this.onSend, required this.controller});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: 'Message...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(24)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.send),
              onPressed: onSend,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final String text;
  final bool isMe;
  final String status;

  const _ChatBubble({
    required this.text,
    required this.isMe,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isMe ? Colors.blue : Colors.grey.shade800,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(text),
            ),
            if (isMe)
              Text(
                status,
                style: const TextStyle(fontSize: 10, color: Colors.white54),
              ),
          ],
        ),
      ),
    );
  }
}
