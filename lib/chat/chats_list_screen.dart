import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'chat_screen.dart';
import 'start_conversation_screen.dart';

class ChatsListScreen extends StatelessWidget {
  const ChatsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Messages',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_square),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const StartConversationScreen(),
                ),
              );
            },
          ),
        ],
      ),

      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('chats')
            .where('members', arrayContains: uid)
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(child: Text('Failed to load messages'));
          }

          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snap.hasData || snap.data!.docs.isEmpty) {
            return const _EmptyMessagesState();
          }

          // 🔥 SAFELY SORT IN DART
          final chats = snap.data!.docs.toList()
            ..sort((a, b) {
              final aTime =
              (a['lastMessageAt'] as Timestamp?)?.toDate();
              final bTime =
              (b['lastMessageAt'] as Timestamp?)?.toDate();

              if (aTime == null && bTime == null) return 0;
              if (aTime == null) return 1;
              if (bTime == null) return -1;

              return bTime.compareTo(aTime);
            });

          return ListView.separated(
            itemCount: chats.length,
            separatorBuilder: (_, __) => const Divider(indent: 72),
            itemBuilder: (context, index) {
              final data = chats[index].data() as Map<String, dynamic>;
              final members = List<String>.from(data['members']);
              final peerUid =
              members.firstWhere((id) => id != uid);

              return _ChatTile(
                peerUid: peerUid,
                lastMessage: data['lastMessage'] ?? '',
              );
            },
          );
        },
      ),
    );
  }
}

// =====================================================
// CHAT TILE
// =====================================================

class _ChatTile extends StatelessWidget {
  final String peerUid;
  final String lastMessage;

  const _ChatTile({
    required this.peerUid,
    required this.lastMessage,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(peerUid)
          .get(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const ListTile(
            leading: CircleAvatar(),
            title: Text('Loading...'),
          );
        }

        final user = snap.data!.data() as Map<String, dynamic>?;
        if (user == null) return const SizedBox.shrink();

        return ListTile(
          leading: CircleAvatar(
            radius: 24,
            backgroundImage: user['photoUrl'] != null
                ? NetworkImage(user['photoUrl'])
                : null,
            child: user['photoUrl'] == null
                ? const Icon(Icons.person)
                : null,
          ),
          title: Text(
            user['name'] ?? 'User',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            lastMessage.isEmpty ? 'Tap to chat' : lastMessage,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatScreen(peerUid: peerUid),
              ),
            );
          },
        );
      },
    );
  }
}

// =====================================================
// EMPTY STATE
// =====================================================

class _EmptyMessagesState extends StatelessWidget {
  const _EmptyMessagesState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 64),
          SizedBox(height: 12),
          Text(
            'No conversations yet',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}