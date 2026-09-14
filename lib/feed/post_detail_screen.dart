import 'package:flutter/material.dart';

import '../services/storage_service.dart';
import '../profile/profile_screen.dart';
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

  @override
  Widget build(BuildContext context) {
    final storage = StorageService();

    final mediaPath = data['media_path'] as String?;
    final userId = data['user_id'] as String?;
    final caption = data['text'] as String?;
    final likesCount = (data['likes_count'] ?? 0) as int;
    final commentsCount = (data['comments_count'] ?? 0) as int;

    if (mediaPath == null || userId == null) {
      return const Scaffold(
        body: Center(child: Text('Invalid post')),
      );
    }

    final imageUrl = storage.getPublicPostUrl(mediaPath);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Post'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          // ================= USER HEADER =================
          PostUserHeader(
            userId: userId,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ProfileScreen(userId: userId),
                ),
              );
            },
          ),

          // ================= IMAGE =================
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.network(
              imageUrl,
              fit: BoxFit.cover,
              width: double.infinity,
            ),
          ),

          // ================= CAPTION =================
          if (caption != null && caption.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                caption,
                style: const TextStyle(fontSize: 15, height: 1.4),
              ),
            ),

          // ================= ACTIONS =================
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                _ActionButton(
                  icon: Icons.favorite,
                  color: Colors.redAccent,
                  count: likesCount,
                ),
                const SizedBox(width: 20),
                _ActionButton(
                  icon: Icons.chat_bubble_outline,
                  color: Colors.white70,
                  count: commentsCount,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CommentsScreen(postId: postId),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/* =========================================================
   ACTION BUTTON
   ========================================================= */

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final int count;
  final Color color;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    required this.count,
    required this.color,
    this.onTap,
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
          Text(
            count.toString(),
            style: const TextStyle(fontSize: 14),
          ),
        ],
      ),
    );
  }
}