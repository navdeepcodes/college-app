import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/storage_service.dart';
import '../profile/profile_screen.dart';
import '../core/app_colors.dart';
import '../core/spacing.dart';
import '../core/widgets/like_button.dart';
import 'comments_screen.dart';
import 'post_user_header.dart';

class PostDetailScreen extends StatelessWidget {
  final String postId;
  final Map<String, dynamic> data;

  const PostDetailScreen({
    super.key,
    required this.postId,
    required this.data,
  });

  Future<void> _toggleLike(String uid) async {
    final supabase = Supabase.instance.client;
    final existing = await supabase
        .from('post_likes')
        .select('id')
        .eq('post_id', postId)
        .eq('user_id', uid)
        .limit(1);

    if (existing.isNotEmpty) {
      await supabase.from('post_likes').delete().eq('post_id', postId).eq('user_id', uid);
    } else {
      await supabase.from('post_likes').insert({'post_id': postId, 'user_id': uid});
    }
  }

  @override
  Widget build(BuildContext context) {
    final storage = StorageService();
    final uid = Supabase.instance.client.auth.currentUser?.id;

    final mediaPath = data['media_path'] as String?;
    final userId = data['user_id'] as String?;
    final caption = data['text'] as String?;
    final commentsCount = (data['comments_count'] ?? 0) as int;

    if (userId == null) {
      return const Scaffold(
        body: Center(child: Text('Invalid post')),
      );
    }

    final imageUrl = mediaPath != null ? storage.getPublicPostUrl(mediaPath) : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Post')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpace.xl),
        children: [
          PostUserHeader(
            userId: userId,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ProfileScreen(userId: userId)),
            ),
          ),
          if (imageUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Image.network(imageUrl, fit: BoxFit.cover, width: double.infinity),
            ),
          if (caption != null && caption.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(caption, style: const TextStyle(fontSize: 15, height: 1.4)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 16, 16),
            child: Row(
              children: [
                if (uid != null)
                  StreamBuilder<List<Map<String, dynamic>>>(
                    stream: Supabase.instance.client
                        .from('post_likes')
                        .stream(primaryKey: ['id'])
                        .eq('post_id', postId),
                    builder: (context, likeSnap) {
                      final isLiked = (likeSnap.data ?? []).any((l) => l['user_id'] == uid);
                      final likesCount = likeSnap.data?.length ?? (data['likes_count'] ?? 0) as int;
                      return LikeButton(
                        isLiked: isLiked,
                        count: likesCount,
                        onToggle: () => _toggleLike(uid),
                      );
                    },
                  ),
                const SizedBox(width: 12),
                InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => CommentsScreen(postId: postId)),
                  ),
                  borderRadius: BorderRadius.circular(24),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.chat_bubble_outline_rounded,
                            size: 22, color: AppColors.textSecondary),
                        const SizedBox(width: 6),
                        Text(
                          '$commentsCount',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
