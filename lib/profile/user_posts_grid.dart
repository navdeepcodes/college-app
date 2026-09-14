import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:college_app/services/storage_service.dart';
import 'package:college_app/feed/post_detail_screen.dart';
import 'package:college_app/utils/dedupe_stream_rows.dart';
import 'package:college_app/core/app_colors.dart';
import 'package:college_app/core/widgets/empty_state.dart';
import 'package:college_app/core/widgets/skeleton.dart';

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
            padding: EdgeInsets.symmetric(vertical: 24),
            child: EmptyState(
              icon: Icons.error_outline_rounded,
              title: "Couldn't load posts",
              isError: true,
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(2),
            itemCount: 6,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
            ),
            itemBuilder: (_, __) => const Skeleton(borderRadius: BorderRadius.zero),
          );
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: EmptyState(
              icon: Icons.grid_view_outlined,
              title: 'No posts yet',
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
            final hasMedia = mediaPath != null && mediaPath.isNotEmpty;

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
              child: hasMedia
                  ? ClipRRect(
                      child: Image.network(
                        storage.getPublicPostUrl(mediaPath),
                        fit: BoxFit.cover,
                        // Grid thumbnails render at roughly a third of
                        // screen width — decoding the full-resolution feed
                        // image here wastes memory 9x over for a tile
                        // this small.
                        cacheWidth: 360,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return const Skeleton(borderRadius: BorderRadius.zero);
                        },
                        errorBuilder: (_, __, ___) {
                          return Container(
                            color: AppColors.surfaceSunken,
                            child: const Center(
                              child: Icon(
                                Icons.lock_outline,
                                size: 24,
                                color: AppColors.textMuted,
                              ),
                            ),
                          );
                        },
                      ),
                    )
                  // A text-only post (media_path is nullable in the
                  // schema) has no thumbnail to show -- found live, three
                  // real posts silently vanishing from this grid entirely
                  // because of an unconditional early-return here.
                  // Rendering a text tile keeps the grid's count matching
                  // the profile's real post count instead of quietly
                  // dropping some of them.
                  : Container(
                      color: AppColors.surfaceSunken,
                      padding: const EdgeInsets.all(8),
                      alignment: Alignment.center,
                      child: Text(
                        (data['text'] as String?)?.trim().isNotEmpty == true
                            ? data['text'] as String
                            : 'Post',
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ),
            );
          },
        );
      },
    );
  }
}
