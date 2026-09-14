import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../clubs/admin_club_requests_screen.dart';
import '../services/friend_service.dart';
import '../utils/dedupe_stream_rows.dart';
import '../core/app_colors.dart';
import '../core/haptics.dart';
import '../core/spacing.dart';
import '../core/widgets/avatar.dart';
import '../core/widgets/empty_state.dart';
import '../core/widgets/entrance.dart';
import '../core/widgets/relative_time.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Please login again')),
      );
    }

    final uid = user.id;

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: Supabase.instance.client
            .from('notifications')
            .stream(primaryKey: ['id'])
            .eq('to_uid', uid)
            .order('created_at', ascending: false)
            .limit(100),
        builder: (context, snap) {
          if (snap.hasError) {
            return const EmptyState(
              icon: Icons.error_outline_rounded,
              title: "Couldn't load notifications",
              isError: true,
            );
          }

          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snap.hasData || snap.data!.isEmpty) {
            return const EmptyState(
              icon: Icons.notifications_none_rounded,
              title: 'No notifications',
              message: "You're all caught up.",
            );
          }

          final docs = dedupeStreamRowsById(snap.data!);

          return ListView.builder(
            padding: const EdgeInsets.all(AppSpace.md),
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final data = docs[i];
              final createdAtRaw = data['created_at'] as String?;
              final createdAt = createdAtRaw != null ? DateTime.tryParse(createdAtRaw) : null;

              Widget? tile;
              if (data['type'] == 'friend_request' &&
                  data['from_uid'] != null &&
                  data['request_id'] != null) {
                tile = _FriendRequestTile(
                  notificationId: data['id'] as String,
                  requestId: data['request_id'] as String,
                  fromUid: data['from_uid'] as String,
                  createdAt: createdAt,
                );
              } else if (data['type'] == 'club_request') {
                tile = _ClubRequestTile(
                  notificationId: data['id'] as String,
                  clubName: data['club_name'] ?? '',
                  createdAt: createdAt,
                );
              }

              if (tile == null) return const SizedBox.shrink();

              return Entrance(
                key: ValueKey(data['id']),
                delay: Duration(milliseconds: 25 * i),
                child: tile,
              );
            },
          );
        },
      ),
    );
  }
}

// =====================================================
// SHARED NOTIFICATION CARD SHELL
// =====================================================

class _NotificationCard extends StatelessWidget {
  final Widget leading;
  final String title;
  final String subtitle;
  final DateTime? createdAt;
  final Widget actions;

  const _NotificationCard({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.createdAt,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.md),
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              leading,
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 3),
                    Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              if (createdAt != null)
                Text(
                  relativeTime(createdAt!),
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          actions,
        ],
      ),
    );
  }
}

// =====================================================
// CLUB REQUEST TILE
// =====================================================

class _ClubRequestTile extends StatelessWidget {
  final String notificationId;
  final String clubName;
  final DateTime? createdAt;

  const _ClubRequestTile({
    required this.notificationId,
    required this.clubName,
    required this.createdAt,
  });

  @override
  Widget build(BuildContext context) {
    return _NotificationCard(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.accent.withValues(alpha: 0.18),
        ),
        child: const Icon(Icons.groups_rounded, color: AppColors.accentBright, size: 20),
      ),
      title: 'New club request',
      subtitle: clubName.isEmpty
          ? 'A student wants to start a club'
          : '$clubName wants to join TrueKinn',
      createdAt: createdAt,
      actions: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              child: const Text('Dismiss'),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await Supabase.instance.client
                      .from('notifications')
                      .delete()
                      .eq('id', notificationId);
                } catch (e) {
                  debugPrint('Dismiss notification failed: $e');
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Could not dismiss. Try again.')),
                  );
                }
              },
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: ElevatedButton(
              child: const Text('Review'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AdminClubRequestsScreen()),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================
// FRIEND REQUEST TILE
// =====================================================

class _FriendRequestTile extends StatefulWidget {
  final String notificationId;
  final String requestId;
  final String fromUid;
  final DateTime? createdAt;

  const _FriendRequestTile({
    required this.notificationId,
    required this.requestId,
    required this.fromUid,
    required this.createdAt,
  });

  @override
  State<_FriendRequestTile> createState() => _FriendRequestTileState();
}

class _FriendRequestTileState extends State<_FriendRequestTile> {
  bool _busy = false;

  Future<void> _respond(bool accept) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final myUid = Supabase.instance.client.auth.currentUser!.id;
      if (accept) {
        await FriendService.acceptRequest(
          requestId: widget.requestId,
          fromUid: widget.fromUid,
          toUid: myUid,
        );
        AppHaptics.confirm();
      } else {
        await FriendService.declineRequest(requestId: widget.requestId);
      }
      // FriendService already deleted the notification row server-side at
      // this point, so the parent list's stream should remove this tile
      // shortly -- but found live, on-device, watching it happen: the
      // Realtime delete event can lag well behind the write actually
      // completing, and this tile has no timeout of its own, so it was
      // left permanently spinning (not a flicker -- confirmed by leaving
      // it on screen and separately confirming via direct query that the
      // request and notification rows were already gone). Resetting
      // _busy here is safe even if the stream removal wins the race
      // first (this whole tile is gone by then, so the setState below is
      // a no-op on an unmounted State): both FriendService calls are
      // idempotent against a row that's already deleted, so a stray
      // second tap while briefly re-enabled just no-ops rather than
      // erroring.
      if (mounted) setState(() => _busy = false);
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Something went wrong. Try again.')),
        );
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('profiles')
          .stream(primaryKey: ['id'])
          .eq('id', widget.fromUid)
          .limit(1),
      builder: (context, snap) {
        final user = (snap.data?.isNotEmpty ?? false) ? snap.data!.first : null;
        final name = user?['name'] ?? 'Someone';

        return _NotificationCard(
          leading: AppAvatar(photoUrl: user?['photo_url'], name: name, radius: 20),
          title: 'Friend request',
          subtitle: '$name wants to be friends',
          createdAt: widget.createdAt,
          actions: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _respond(false),
                  child: const Text('Reject'),
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: ElevatedButton(
                  onPressed: _busy ? null : () => _respond(true),
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Accept'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
