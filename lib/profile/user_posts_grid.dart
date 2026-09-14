import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:college_app/services/storage_service.dart';
import 'package:college_app/feed/post_detail_screen.dart';
import 'package:college_app/utils/dedupe_stream_rows.dart';

class UserPostsGrid extends StatelessWidget {
  final String uid;

  const UserPostsGrid({
    super.key,
    required this.uid,
  });

  @override
  Widget build(BuildContext context) {
    final storage = StorageService();

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('posts')
          .stream(primaryKey: ['id'])
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(60),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'Failed to load posts',
              style: TextStyle(color: Colors.white54),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          );
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(40),
            child: Text(
              'No posts yet',
              style: TextStyle(color: Colors.white54),
            ),
          );
        }

        final posts = dedupeStreamRowsById(snapshot.data!);

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
            final data = posts[index];

            final mediaPath = data['media_path'] as String?;
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
                      postId: data['id'],
                      data: data,
                    ),
                  ),
                );
              },
              child: ClipRRect(
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
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
