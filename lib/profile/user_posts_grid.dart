import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:college_app/services/storage_service.dart';
import 'package:college_app/feed/post_detail_screen.dart';

class UserPostsGrid extends StatelessWidget {
  final String uid;

  const UserPostsGrid({
    super.key,
    required this.uid,
  });

  @override
  Widget build(BuildContext context) {
    final storage = StorageService();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('posts')
          .where('userId', isEqualTo: uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(40),
            child: Text(
              'No posts yet',
              style: TextStyle(color: Colors.white54),
            ),
          );
        }

        final posts = snapshot.data!.docs;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(2),
          itemCount: posts.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
          ),
          itemBuilder: (context, index) {
            final doc = posts[index];
            final data = doc.data() as Map<String, dynamic>;

            final mediaPath = data['mediaPath'] as String?;
            if (mediaPath == null || mediaPath.isEmpty) {
              return const SizedBox.shrink();
            }

            final imageUrl = storage.getPublicPostUrl(mediaPath);

            return GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PostDetailScreen(
                      postId: doc.id,
                      data: data,
                    ),
                  ),
                );
              },
              child: ClipRRect(
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.cover,

                  // 🔹 SMOOTH LOADING
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;

                    return Container(
                      color: Colors.grey.shade900,
                      child: const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    );
                  },

                  // 🔒 FRIENDS-ONLY / ERROR STATE
                  errorBuilder: (_, __, ___) {
                    return Container(
                      color: Colors.grey.shade900,
                      child: const Center(
                        child: Icon(
                          Icons.lock_outline,
                          size: 26,
                          color: Colors.white38,
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}