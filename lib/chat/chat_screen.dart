import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
  final String _currentUid = FirebaseAuth.instance.currentUser!.uid;
  late final String _chatId;

  @override
  void initState() {
    super.initState();

    final ids = [_currentUid, widget.peerUid]..sort();
    _chatId = ids.join('_');

    _ensureChatExists();
    _markDelivered();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _ensureChatExists() async {
    final ref = FirebaseFirestore.instance.collection('chats').doc(_chatId);
    final snap = await ref.get();

    if (!snap.exists) {
      await ref.set({
        'members': [_currentUid, widget.peerUid],
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessage': '',
        'lastMessageAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> _markDelivered() async {
    final snap = await FirebaseFirestore.instance
        .collection('chats')
        .doc(_chatId)
        .collection('messages')
        .where('toUid', isEqualTo: _currentUid)
        .where('status', isEqualTo: 'sent')
        .get();

    for (final d in snap.docs) {
      d.reference.update({'status': 'delivered'});
    }
  }

  Future<void> _markSeen() async {
    final snap = await FirebaseFirestore.instance
        .collection('chats')
        .doc(_chatId)
        .collection('messages')
        .where('toUid', isEqualTo: _currentUid)
        .where('status', isEqualTo: 'delivered')
        .get();

    for (final d in snap.docs) {
      d.reference.update({'status': 'seen'});
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    // Moderation: block messages the content filter rejects (anon-chat policy).
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

    final ref = FirebaseFirestore.instance.collection('chats').doc(_chatId);

    await ref.collection('messages').add({
      'fromUid': _currentUid,
      'toUid': widget.peerUid,
      'text': filterResult.cleanedText,
      'status': 'sent',
      'createdAt': FieldValue.serverTimestamp(),
    });

    await ref.update({
      'lastMessage': filterResult.cleanedText,
      'lastMessageAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(widget.peerUid)
              .snapshots(),
          builder: (_, snap) {
            if (!snap.hasData) return const SizedBox();
            final u = snap.data!.data() as Map<String, dynamic>;

            return Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundImage:
                  u['photoUrl'] != null ? NetworkImage(u['photoUrl']) : null,
                  child: u['photoUrl'] == null
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
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .doc(_chatId)
                  .collection('messages')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (_, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final msgs = snap.data!.docs;

                WidgetsBinding.instance
                    .addPostFrameCallback((_) => _markSeen());

                if (msgs.isEmpty) {
                  return const Center(child: Text('Say hi 👋'));
                }

                return ListView.builder(
                  reverse: true,
                  itemCount: msgs.length,
                  itemBuilder: (_, i) {
                    final d = msgs[i].data() as Map<String, dynamic>;
                    final isMe = d['fromUid'] == _currentUid;

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
      ),
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