import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/storage_service.dart';
import '../notifications/notifications_screen.dart';
import '../chat/chats_list_screen.dart';
import '../profile/profile_screen.dart';
import '../feed/comments_screen.dart';
import 'post_user_header.dart';
import 'add_create_selector_sheet.dart';
import '../auth/services/college_detector.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  late final String _uid;

  late final StorageService _storage;

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser!.uid;

    // ✅ CORRECT: no Supabase.instance here
    _storage = StorageService();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const Text(
          'Campus',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          _TopPillIcon(
            icon: Icons.add,
            onTap: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => const AddCreateSelectorSheet(),
            ),
          ),
          _TopPillIcon(
            icon: Icons.chat_bubble_outline,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ChatsListScreen()),
            ),
          ),
          _TopPillIcon(
            icon: Icons.notifications_none,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const NotificationsScreen(),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Expanded(
        child: _MergedFeed(
          uid: _uid,
          storage: _storage,
        ),
      ),
    );
  }
}

/* =========================================================
   MERGED FEED
   ========================================================= */

class _MergedFeed extends StatelessWidget {
  final String uid;
  final StorageService storage;

  const _MergedFeed({
    required this.uid,
    required this.storage,
  });

  Future<void> _toggleLike(String postId) async {
    final postRef =
    FirebaseFirestore.instance.collection('posts').doc(postId);
    final likeRef = postRef.collection('likes').doc(uid);

    await FirebaseFirestore.instance.runTransaction((txn) async {
      final snap = await txn.get(likeRef);

      if (snap.exists) {
        txn.delete(likeRef);
        txn.update(postRef, {
          'likesCount': FieldValue.increment(-1),
        });
      } else {
        txn.set(likeRef, {
          'userId': uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
        txn.update(postRef, {
          'likesCount': FieldValue.increment(1),
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // The campus feed is college-isolated: resolve the current user's
    // canonical collegeId (users doc) and only stream that college's posts.
    // (Client-side filtering alone is not security; the rules enforce the
    // same binding — see firestore.rules posts block.)
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
      builder: (context, userSnap) {
        final collegeId = userSnap.hasData
            ? canonicalCollegeId(userSnap.data!.data() as Map<String, dynamic>?)
            : '';
        if (collegeId.isEmpty) {
          return const Center(
            child: Text(
              'Complete your profile to see the campus feed',
              style: TextStyle(color: Colors.white70),
            ),
          );
        }

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('posts')
              .where('collegeId', isEqualTo: collegeId)
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const Center(
            child: Text(
              'No posts yet',
              style: TextStyle(color: Colors.white70),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 140),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final postDoc = docs[i];
            final data = postDoc.data() as Map<String, dynamic>;

            final mediaPath = data['mediaPath'];
            final userId = data['userId'];
            if (mediaPath == null || userId == null) {
              return const SizedBox.shrink();
            }

            final imageUrl = storage.getPublicPostUrl(mediaPath);
            final likesCount = (data['likesCount'] ?? 0) as int;
            final commentsCount =
            (data['commentsCount'] ?? 0) as int;

            return StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('posts')
                  .doc(postDoc.id)
                  .collection('likes')
                  .doc(uid)
                  .snapshots(),
              builder: (context, likeSnap) {
                final isLiked =
                    likeSnap.hasData && likeSnap.data!.exists;

                return Card(
                  margin: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PostUserHeader(
                        userId: userId,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                ProfileScreen(userId: userId),
                          ),
                        ),
                      ),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                        ),
                      ),
                      if (data['caption'] is String &&
                          (data['caption'] as String).isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                              14, 10, 14, 0),
                          child: Text(
                            data['caption'] as String,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium,
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                            14, 10, 14, 14),
                        child: Row(
                          children: [
                            _ActionButton(
                              icon: isLiked
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              color: isLiked
                                  ? Colors.redAccent
                                  : Colors.white70,
                              count: likesCount,
                              onTap: () =>
                                  _toggleLike(postDoc.id),
                            ),
                            const SizedBox(width: 18),
                            _ActionButton(
                              icon: Icons.chat_bubble_outline,
                              color: Colors.white70,
                              count: commentsCount,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CommentsScreen(
                                    postId: postDoc.id,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
          );
        },
      );
  }
}

/* =========================================================
   UI COMPONENTS (UNCHANGED)
   ========================================================= */

class _TopPillIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _TopPillIcon({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, size: 20),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final int count;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.count,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Row(
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(width: 6),
          Text(count.toString()),
        ],
      ),
    );
  }
}
