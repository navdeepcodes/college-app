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
  late final Future<void> _ready;

  @override
  void initState() {
    super.initState();

    final ids = [_currentUid, widget.peerUid]..sort();
    _chatId = ids.join('_');

    // The messages stream (and _markDelivered's query) both require
    // isChatMember(chatId) in firestore.rules, which reads the chat doc
    // itself — so they can't safely start until the chat doc is known to
    // exist. Sequenced (not fire-and-forget) so the UI can show a loading
    // state instead of racing a permission-denied error on a brand new
    // conversation.
    _ready = _ensureChatExists().then((_) => _markDelivered());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _ensureChatExists() async {
    final ref = FirebaseFirestore.instance.collection('chats').doc(_chatId);

    bool exists = false;
    try {
      final snap = await ref.get();
      exists = snap.exists;
    } catch (_) {
      // firestore.rules' isChatMember() reads the chat doc to check
      // membership — for a doc that doesn't exist yet, that dereference
      // throws rather than evaluating to "not a member", so .get() on a
      // brand new chat always raises permission-denied instead of
      // returning exists:false. Since _chatId is always derived from our
      // OWN uid + the peer, the only realistic cause here is "doesn't
      // exist yet" — treat any failure as that.
      exists = false;
    }

    if (exists) return;

    // members must be in the same sorted order as _chatId/ids: the
    // firestore.rules chats.create rule requires members[0] < members[1].
    // Writing the unsorted [_currentUid, peerUid] pair here made chat
    // creation permission-denied for roughly half of all user pairs
    // (whenever _currentUid sorted after peerUid).
    final ids = [_currentUid, widget.peerUid]..sort();
    try {
      await ref.set({
        'members': ids,
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessage': '',
        'lastMessageAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Lost a create race to the peer opening this same chat at the same
      // moment — the doc now exists with the same shape either way.
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

    if (snap.docs.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final d in snap.docs) {
      batch.update(d.reference, {'status': 'delivered'});
    }
    await batch.commit();
  }

  Future<void> _markSeen() async {
    final snap = await FirebaseFirestore.instance
        .collection('chats')
        .doc(_chatId)
        .collection('messages')
        .where('toUid', isEqualTo: _currentUid)
        .where('status', isEqualTo: 'delivered')
        .get();

    if (snap.docs.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final d in snap.docs) {
      batch.update(d.reference, {'status': 'seen'});
    }
    await batch.commit();
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
            if (!snap.hasData || !snap.data!.exists) return const SizedBox();
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
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .doc(_chatId)
                  .collection('messages')
                  .orderBy('createdAt', descending: true)
                  .limit(50)
                  .snapshots(),
              builder: (_, snap) {
                if (snap.hasError) {
                  return const Center(
                    child: Text('Failed to load messages'),
                  );
                }

                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final msgs = snap.data!.docs;

                // Only worth a _markSeen() round-trip when this snapshot
                // actually contains something the peer would want marked —
                // avoids a redundant query+writes on every unrelated rebuild
                // (e.g. our own optimistic send).
                final hasUnseen = msgs.any((m) {
                  final d = m.data() as Map<String, dynamic>;
                  return d['toUid'] == _currentUid && d['status'] == 'delivered';
                });
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