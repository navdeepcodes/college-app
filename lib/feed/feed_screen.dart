import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/storage_service.dart';
import '../notifications/notifications_screen.dart';
import '../chat/chats_list_screen.dart';
import '../moments/moments_screen.dart';
import '../profile/profile_screen.dart';
import '../feed/comments_screen.dart';
import 'post_user_header.dart';
import 'add_create_selector_sheet.dart';
import 'events_screen.dart';
import '../auth/services/college_detector.dart';

// Moments is restored in the codebase (screens, storage upload path,
// Postgres schema/RLS) but intentionally not user-reachable: it's not
// part of the current live product. Flip this to re-enable the entry point.
const bool kMomentsEnabled = false;

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
    _uid = Supabase.instance.client.auth.currentUser!.id;
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
          if (kMomentsEnabled)
            _TopPillIcon(
              icon: Icons.bolt_outlined,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MomentsScreen()),
              ),
            ),
          _TopPillIcon(
            icon: Icons.event_outlined,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const EventsScreen()),
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
    final supabase = Supabase.instance.client;

    final existing = await supabase
        .from('post_likes')
        .select('id')
        .eq('post_id', postId)
        .eq('user_id', uid)
        .limit(1);

    if (existing.isNotEmpty) {
      await supabase
          .from('post_likes')
          .delete()
          .eq('post_id', postId)
          .eq('user_id', uid);
    } else {
      await supabase.from('post_likes').insert({
        'post_id': postId,
        'user_id': uid,
      });
    }
    // likes_count is trigger-maintained (bump_post_likes_count) — no
    // client-side increment needed or possible.
  }

  @override
  Widget build(BuildContext context) {
    final supabase = Supabase.instance.client;

    // The campus feed is college-isolated: resolve the current user's
    // canonical collegeId and only stream that college's posts.
    // (Client-side filtering alone is not security; RLS enforces the same
    // binding — see supabase/migrations/20260914000002_rls_policies.sql.)
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: supabase.from('profiles').select().eq('id', uid).limit(1),
      builder: (context, userSnap) {
        if (userSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (userSnap.hasError) {
          return const Center(
            child: Text(
              'Failed to load your profile',
              style: TextStyle(color: Colors.white70),
            ),
          );
        }

        final collegeId = (userSnap.data?.isNotEmpty ?? false)
            ? canonicalCollegeId(userSnap.data!.first)
            : '';
        if (collegeId.isEmpty) {
          return const Center(
            child: Text(
              'Complete your profile to see the campus feed',
              style: TextStyle(color: Colors.white70),
            ),
          );
        }

        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: supabase
              .from('posts')
              .stream(primaryKey: ['id'])
              .eq('college_id', collegeId)
              .order('created_at', ascending: false)
              .limit(50),
          builder: (context, snap) {
            if (snap.hasError) {
              return const Center(
                child: Text(
                  'Failed to load the feed',
                  style: TextStyle(color: Colors.white70),
                ),
              );
            }

            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final docs = snap.data!;
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
                final data = docs[i];
                final postId = data['id'] as String;

                final mediaPath = data['media_path'];
                final userId = data['user_id'];
                if (mediaPath == null || userId == null) {
                  return const SizedBox.shrink();
                }

                final imageUrl = storage.getPublicPostUrl(mediaPath);
                final likesCount = (data['likes_count'] ?? 0) as int;
                final commentsCount = (data['comments_count'] ?? 0) as int;

                return StreamBuilder<List<Map<String, dynamic>>>(
                  stream: supabase
                      .from('post_likes')
                      .stream(primaryKey: ['id'])
                      .eq('post_id', postId),
                  builder: (context, likeSnap) {
                    final isLiked = (likeSnap.data ?? [])
                        .any((l) => l['user_id'] == uid);

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
                                builder: (_) => ProfileScreen(userId: userId),
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
                          if (data['text'] is String &&
                              (data['text'] as String).isNotEmpty)
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(14, 10, 14, 0),
                              child: Text(
                                data['text'] as String,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
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
                                  onTap: () => _toggleLike(postId),
                                ),
                                const SizedBox(width: 18),
                                _ActionButton(
                                  icon: Icons.chat_bubble_outline,
                                  color: Colors.white70,
                                  count: commentsCount,
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          CommentsScreen(postId: postId),
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
            color: Colors.white.withValues(alpha: 0.08),
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
