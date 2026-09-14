import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../feed/widgets/friend_button.dart';
import '../settings/settings_screen.dart';
import '../services/moderation_service.dart';
import '../moderation/report_dialog.dart';
import '../core/app_colors.dart';
import '../core/haptics.dart';
import '../core/spacing.dart';
import '../core/widgets/avatar.dart';
import '../core/widgets/entrance.dart';
import 'edit_profile_screen.dart';
import 'user_posts_grid.dart';
import 'friends_list_screen.dart';

class ProfileScreen extends StatelessWidget {
  final String userId;

  const ProfileScreen({super.key, required this.userId});

  Future<void> _confirmBlock(BuildContext context, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Block this person?'),
        content: Text(
          "$name won't be able to message you or send friend requests. "
          'You can unblock them anytime from their profile.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Block', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    AppHaptics.warn();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ModerationService.blockUser(userId);
      messenger.showSnackBar(SnackBar(content: Text('$name is blocked')));
    } catch (e) {
      debugPrint('Block failed: $e');
      final already = e.toString().contains('23505');
      messenger.showSnackBar(
        SnackBar(content: Text(already ? 'Already blocked.' : 'Something went wrong. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = Supabase.instance.client.auth.currentUser?.id;
    final isMe = currentUid == userId;

    if (currentUid == null) {
      return const Scaffold(
        body: Center(child: Text('Please login again')),
      );
    }

    final pair = ([currentUid, userId]..sort());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: isMe
            ? [
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ),
                ),
              ]
            : [
                StreamBuilder<List<Map<String, dynamic>>>(
                  stream: Supabase.instance.client
                      .from('profiles')
                      .stream(primaryKey: ['id'])
                      .eq('id', userId)
                      .limit(1),
                  builder: (context, snap) {
                    final name = (snap.data?.isNotEmpty ?? false)
                        ? (snap.data!.first['name'] ?? 'This user')
                        : 'This user';

                    return PopupMenuButton<String>(
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'report', child: Text('Report user')),
                        PopupMenuItem(value: 'block', child: Text('Block user')),
                        PopupMenuItem(value: 'unblock', child: Text('Unblock user')),
                      ],
                      onSelected: (value) async {
                        if (value == 'report') {
                          await showReportDialog(context, targetType: 'user', targetId: userId);
                          return;
                        }
                        if (value == 'block') {
                          await _confirmBlock(context, name);
                          return;
                        }
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          await ModerationService.unblockUser(userId);
                          messenger.showSnackBar(const SnackBar(content: Text('User unblocked')));
                        } catch (e) {
                          debugPrint('Unblock failed: $e');
                          messenger.showSnackBar(
                            const SnackBar(content: Text('Something went wrong. Try again.')),
                          );
                        }
                      },
                    );
                  },
                ),
              ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: Supabase.instance.client
            .from('profiles')
            .stream(primaryKey: ['id'])
            .eq('id', userId)
            .limit(1),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snap.data!.isEmpty) {
            return const Center(child: Text('User not found'));
          }

          final user = snap.data!.first;
          final photoUrl = user['photo_url'];
          final name = user['name'] ?? '';
          final nickname = user['nickname'];
          final bio = user['bio'];
          final college = user['college'] ?? '';
          final year = user['year'] ?? '';

          return StreamBuilder<List<Map<String, dynamic>>>(
            stream: Supabase.instance.client
                .from('friendships')
                .stream(primaryKey: ['id'])
                .eq('user_a', pair[0])
                .eq('user_b', pair[1]),
            builder: (context, friendsSnap) {
              final isFriend = (friendsSnap.data ?? []).isNotEmpty;

              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.xxl),
                child: Column(
                  children: [
                    Entrance(
                      child: AppAvatar(photoUrl: photoUrl, name: name, radius: 52),
                    ),
                    const SizedBox(height: AppSpace.md),
                    Text(name, style: Theme.of(context).textTheme.titleLarge),
                    if (nickname != null && nickname.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('@$nickname',
                            style: const TextStyle(color: AppColors.textMuted)),
                      ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceRaised,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        [college, year].where((s) => s.toString().isNotEmpty).join(' · '),
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (bio != null && bio.isNotEmpty) ...[
                      const SizedBox(height: AppSpace.md),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          bio,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpace.xl),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _CountItem(label: 'Posts', value: user['posts_count'] ?? 0),
                        _CountItem(
                          label: 'Friends',
                          value: user['friends_count'] ?? 0,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => FriendsListScreen(userId: userId)),
                          ),
                        ),
                        _CountItem(label: 'Clubs', value: user['clubs_count'] ?? 0),
                      ],
                    ),
                    const SizedBox(height: AppSpace.xl),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxl),
                      child: isMe
                          ? OutlinedButton(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const EditProfileScreen()),
                              ),
                              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                              child: const Text('Edit profile'),
                            )
                          : FriendButton(targetUserId: userId),
                    ),
                    const SizedBox(height: AppSpace.xxl),
                    const Divider(indent: 24, endIndent: 24),
                    const SizedBox(height: 4),
                    if (isMe || isFriend)
                      UserPostsGrid(uid: userId)
                    else
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'Only friends can see posts',
                          style: TextStyle(color: AppColors.textMuted),
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

class _CountItem extends StatelessWidget {
  final String label;
  final int value;
  final VoidCallback? onTap;

  const _CountItem({required this.label, required this.value, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Column(
          children: [
            Text(
              value.toString(),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
          ],
        ),
      ),
    );
  }
}
