import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../feed/widgets/friend_button.dart';

class PublicProfileScreen extends StatelessWidget {
  final String userId;

  const PublicProfileScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final isMe = currentUid == userId;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Profile')),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final user = snap.data!.data() as Map<String, dynamic>;
          final photoUrl = user['photoUrl'];

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.white.withOpacity(0.08),
                  backgroundImage:
                  photoUrl != null ? NetworkImage(photoUrl) : null,
                  child:
                  photoUrl == null ? const Icon(Icons.person, size: 44) : null,
                ),
                const SizedBox(height: 12),
                Text(
                  user['name'] ?? '',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${user['college'] ?? ''} • ${user['year'] ?? ''}',
                  style: const TextStyle(color: Colors.white54),
                ),
                const SizedBox(height: 20),
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: FriendButton(targetUserId: userId),
                  ),
                const SizedBox(height: 32),
                const Text(
                  'Posts are private',
                  style: TextStyle(color: Colors.white54),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}