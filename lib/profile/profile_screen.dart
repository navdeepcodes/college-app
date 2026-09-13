import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../feed/widgets/friend_button.dart';
import '../settings/settings_screen.dart';
import 'edit_profile_screen.dart';
import 'user_posts_grid.dart';
import 'friends_list_screen.dart';

class ProfileScreen extends StatelessWidget {
  final String userId;

  const ProfileScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final isMe = currentUid == userId;

    if (currentUid == null) {
      return const Scaffold(
        body: Center(child: Text('Please login again')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Profile'),
        actions: isMe
            ? [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SettingsScreen(),
                ),
              );
            },
          ),
        ]
            : null,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snap.data!.exists) {
            return const Center(child: Text('User not found'));
          }

          final user = snap.data!.data() as Map<String, dynamic>;
          final photoUrl = user['photoUrl'];
          final name = user['name'] ?? '';
          final nickname = user['nickname'];
          final bio = user['bio'];
          final college = user['college'] ?? '';
          final year = user['year'] ?? '';

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('friends')
                .where('members', arrayContains: currentUid)
                .snapshots(),
            builder: (context, friendsSnap) {
              final isFriend = friendsSnap.hasData &&
                  friendsSnap.data!.docs.any((d) =>
                      List<String>.from(d['members']).contains(userId));

              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 54,
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                      backgroundImage:
                      photoUrl != null ? NetworkImage(photoUrl) : null,
                      child: photoUrl == null
                          ? const Icon(Icons.person, size: 44)
                          : null,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (nickname != null && nickname.isNotEmpty)
                      Text(
                        '@$nickname',
                        style: const TextStyle(color: Colors.white60),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      '$college • $year',
                      style: const TextStyle(color: Colors.white54),
                    ),
                    if (bio != null && bio.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          bio,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _CountItem(
                          label: 'Posts',
                          value: user['postsCount'] ?? 0,
                        ),
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    FriendsListScreen(userId: userId),
                              ),
                            );
                          },
                          child: _CountItem(
                            label: 'Friends',
                            value: user['friendsCount'] ?? 0,
                          ),
                        ),
                        _CountItem(
                          label: 'Clubs',
                          value: user['clubsCount'] ?? 0,
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: isMe
                          ? _pillButton(
                        text: 'Edit Profile',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                              const EditProfileScreen(),
                            ),
                          );
                        },
                      )
                          : _FriendActionButton(
                        currentUid: currentUid,
                        targetUid: userId,
                      ),
                    ),
                    const SizedBox(height: 28),
                    const Divider(color: Colors.white12),
                    if (isMe || isFriend)
                      UserPostsGrid(uid: userId)
                    else
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'Only friends can see posts',
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _FriendActionButton extends StatelessWidget {
  final String currentUid;
  final String targetUid;

  const _FriendActionButton({
    required this.currentUid,
    required this.targetUid,
  });

  @override
  Widget build(BuildContext context) {
    return FriendButton(targetUserId: targetUid);
  }
}

Widget _pillButton({
  required String text,
  required VoidCallback onTap,
}) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
  );
}

class _CountItem extends StatelessWidget {
  final String label;
  final int value;

  const _CountItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value.toString(),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        Text(label, style: const TextStyle(color: Colors.white54)),
      ],
    );
  }
}