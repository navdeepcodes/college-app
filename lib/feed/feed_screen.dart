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
import '../utils/dedupe_stream_rows.dart';
import '../moderation/report_dialog.dart';
import '../core/app_colors.dart';
import '../core/spacing.dart';
import '../core/widgets/empty_state.dart';
import '../core/widgets/entrance.dart';
import '../core/widgets/like_button.dart';
import '../core/widgets/pressable.dart';
import '../core/widgets/skeleton.dart';

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
        titleSpacing: 20,
        title: const Text('Campus'),
        actions: [
          _TopPillIcon(
            icon: Icons.add_rounded,
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
            icon: Icons.chat_bubble_outline_rounded,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ChatsListScreen()),
            ),
          ),
          _TopPillIcon(
            icon: Icons.notifications_none_rounded,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _MergedFeed(uid: _uid, storage: _storage),
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

  // Keyed by postId rather than held as instance state -- _MergedFeed is a
  // StatelessWidget rebuilt on every feed stream emission, so an instance
  // field would never survive between taps. A static set shared across
  // rebuilds is the smallest guard against the same postId's like button
  // being double-tapped before the first request resolves, without
  // converting the whole feed card tree to Stateful just for this.
  static final Set<String> _pendingLikes = <String>{};

  Future<void> _toggleLike(BuildContext context, String postId) async {
    if (_pendingLikes.contains(postId)) return;
    _pendingLikes.add(postId);
    final supabase = Supabase.instance.client;

    try {
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
    } catch (e) {
      debugPrint('Toggle like failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update like. Try again.')),
        );
      }
      rethrow;
    } finally {
      _pendingLikes.remove(postId);
    }
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
          return const _FeedSkeleton();
        }

        if (userSnap.hasError) {
          return const EmptyState(
            icon: Icons.wifi_off_rounded,
            title: "Couldn't load your profile",
            message: 'Check your connection and reopen this tab.',
            isError: true,
          );
        }

        final collegeId = (userSnap.data?.isNotEmpty ?? false)
            ? canonicalCollegeId(userSnap.data!.first)
            : '';
        if (collegeId.isEmpty) {
          return const EmptyState(
            icon: Icons.badge_outlined,
            title: 'Finish your profile',
            message: 'Complete your profile to see the campus feed.',
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
              return const EmptyState(
                icon: Icons.error_outline_rounded,
                title: "Couldn't load the feed",
                message: 'Pull down to try again.',
                isError: true,
              );
            }

            if (!snap.hasData) {
              return const _FeedSkeleton();
            }

            final docs = dedupeStreamRowsById(snap.data!);
            if (docs.isEmpty) {
              return EmptyState(
                icon: Icons.dynamic_feed_outlined,
                title: 'No posts yet',
                message: 'Be the first to share something with your campus.',
                actionLabel: 'Create a post',
                onAction: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const AddCreateSelectorSheet(),
                ),
              );
            }

            return RefreshIndicator(
              color: AppColors.accentBright,
              backgroundColor: AppColors.surfaceRaised,
              onRefresh: () async {
                // The feed is already Realtime-live; this exists for the
                // reassurance gesture users expect on any feed, and
                // resolves as soon as the current stream snapshot repaints.
                await Future<void>.delayed(const Duration(milliseconds: 400));
              },
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 140, top: 4),
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final data = docs[i];
                  final postId = data['id'] as String;

                  final mediaPath = data['media_path'] as String?;
                  final userId = data['user_id'];
                  // media_path is nullable in the schema (a post can be
                  // text-only), even though today's compose screen always
                  // attaches an image -- found live, on-device: 3 existing
                  // text-only posts were silently vanishing from the feed
                  // (unconditionally SizedBox.shrink()'d) while still
                  // counting toward `docs`, so the feed rendered as a
                  // blank screen instead of either the posts or the
                  // "No posts yet" empty state. Render what the post
                  // actually has instead of assuming a photo.
                  if (userId == null) {
                    return const SizedBox.shrink();
                  }

                  final imageUrl = mediaPath != null ? storage.getPublicPostUrl(mediaPath) : null;
                  final likesCount = (data['likes_count'] ?? 0) as int;
                  final commentsCount = (data['comments_count'] ?? 0) as int;

                  return Entrance(
                    key: ValueKey(postId),
                    child: StreamBuilder<List<Map<String, dynamic>>>(
                      stream: supabase
                          .from('post_likes')
                          .stream(primaryKey: ['id'])
                          .eq('post_id', postId),
                      builder: (context, likeSnap) {
                        final isLiked =
                            (likeSnap.data ?? []).any((l) => l['user_id'] == uid);

                        return Card(
                          margin: const EdgeInsets.symmetric(
                              horizontal: AppSpace.md, vertical: AppSpace.sm),
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
                                trailing: userId == uid
                                    ? null
                                    : PopupMenuButton<String>(
                                        icon: const Icon(Icons.more_vert_rounded, size: 20),
                                        itemBuilder: (context) => [
                                          const PopupMenuItem(
                                            value: 'report',
                                            child: Text('Report post'),
                                          ),
                                        ],
                                        onSelected: (_) {
                                          showReportDialog(
                                            context,
                                            targetType: 'post',
                                            targetId: postId,
                                          );
                                        },
                                      ),
                              ),
                              if (imageUrl != null)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(AppRadius.md),
                                  child: Image.network(
                                    imageUrl,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    loadingBuilder: (context, child, progress) {
                                      if (progress == null) return child;
                                      return const AspectRatio(
                                        aspectRatio: 1.1,
                                        child: Skeleton(borderRadius: BorderRadius.zero),
                                      );
                                    },
                                    errorBuilder: (_, __, ___) => Container(
                                      height: 220,
                                      color: AppColors.surfaceSunken,
                                      alignment: Alignment.center,
                                      child: const Icon(
                                        Icons.broken_image_outlined,
                                        color: AppColors.textMuted,
                                      ),
                                    ),
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
                                padding: const EdgeInsets.fromLTRB(10, 6, 14, 10),
                                child: Row(
                                  children: [
                                    LikeButton(
                                      isLiked: isLiked,
                                      count: likesCount,
                                      onToggle: () => _toggleLike(context, postId),
                                    ),
                                    const SizedBox(width: 10),
                                    _ActionButton(
                                      icon: Icons.chat_bubble_outline_rounded,
                                      color: AppColors.textSecondary,
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
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

class _FeedSkeleton extends StatelessWidget {
  const _FeedSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
      itemCount: 3,
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.md),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.all(AppSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Skeleton(width: 36, height: 36, borderRadius: BorderRadius.all(Radius.circular(18))),
                  const SizedBox(width: 10),
                  Skeleton(width: 100, height: 12, borderRadius: BorderRadius.circular(6)),
                ],
              ),
              const SizedBox(height: 12),
              const AspectRatio(
                aspectRatio: 1.2,
                child: Skeleton(borderRadius: BorderRadius.all(Radius.circular(16))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* =========================================================
   UI COMPONENTS
   ========================================================= */

class _TopPillIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _TopPillIcon({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Pressable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
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
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(width: 6),
            Text(count.toString(), style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13.5)),
          ],
        ),
      ),
    );
  }
}
