import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'chat_screen.dart';

class StartConversationScreen extends StatelessWidget {
  const StartConversationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Start a conversation'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('friends')
            .where('members', arrayContains: currentUid)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snap.hasData || snap.data!.docs.isEmpty) {
            return const Center(
              child: Text('No friends yet'),
            );
          }

          final friendDocs = snap.data!.docs;

          return ListView.builder(
            itemCount: friendDocs.length,
            itemBuilder: (context, index) {
              final members =
              List<String>.from(friendDocs[index]['members']);
              final friendUid =
              members.firstWhere((uid) => uid != currentUid);

              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance
                    .collection('users')
                    .doc(friendUid)
                    .get(),
                builder: (context, userSnap) {
                  if (!userSnap.hasData) {
                    return const SizedBox.shrink();
                  }

                  final user =
                  userSnap.data!.data() as Map<String, dynamic>?;

                  if (user == null) return const SizedBox.shrink();

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: user['photoUrl'] != null
                          ? NetworkImage(user['photoUrl'])
                          : null,
                      child: user['photoUrl'] == null
                          ? const Icon(Icons.person)
                          : null,
                    ),
                    title: Text(user['name'] ?? 'User'),
                    subtitle: Text(
                      '${user['college'] ?? ''} • ${user['year'] ?? ''}',
                    ),
                    trailing: const Icon(Icons.chat_bubble_outline),
                    onTap: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ChatScreen(peerUid: friendUid),
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}