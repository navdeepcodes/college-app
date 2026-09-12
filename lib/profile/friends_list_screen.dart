import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../chat/chat_screen.dart';
import 'profile_screen.dart';

class FriendsListScreen extends StatelessWidget {
  final String userId;

  const FriendsListScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Friends')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('friends')
            .where('members', arrayContains: userId)
            .snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final friendUids = snap.data!.docs
              .expand((doc) =>
          List<String>.from(doc['members']))
              .where((uid) => uid != userId)
              .toSet()
              .toList();

          if (friendUids.isEmpty) {
            return const Center(child: Text('No friends yet'));
          }

          return ListView.builder(
            itemCount: friendUids.length,
            itemBuilder: (context, index) {
              final friendUid = friendUids[index];

              return StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(friendUid)
                    .snapshots(),
                builder: (context, userSnap) {
                  if (!userSnap.hasData) {
                    return const SizedBox.shrink();
                  }

                  final user =
                  userSnap.data!.data() as Map<String, dynamic>;

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: user['photoUrl'] != null
                          ? NetworkImage(user['photoUrl'])
                          : null,
                      child: user['photoUrl'] == null
                          ? const Icon(Icons.person)
                          : null,
                    ),
                    title: Text(user['name'] ?? ''),
                    subtitle: Text(user['college'] ?? ''),
                    trailing: IconButton(
                      icon: const Icon(Icons.chat),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                ChatScreen(peerUid: friendUid),
                          ),
                        );
                      },
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ProfileScreen(userId: friendUid),
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