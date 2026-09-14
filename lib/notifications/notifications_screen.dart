import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../clubs/admin_club_requests_screen.dart';
import '../services/friend_service.dart';
import '../utils/dedupe_stream_rows.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            'Please login again',
            style: TextStyle(color: Colors.white54),
          ),
        ),
      );
    }

    final uid = user.id;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text(
          'Notifications',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: Supabase.instance.client
            .from('notifications')
            .stream(primaryKey: ['id'])
            .eq('to_uid', uid)
            .order('created_at', ascending: false)
            .limit(100),
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(
              child: Text(
                'Failed to load notifications',
                style: TextStyle(color: Colors.white54),
              ),
            );
          }

          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.deepPurple),
            );
          }

          if (!snap.hasData || snap.data!.isEmpty) {
            return const Center(
              child: Text(
                'No notifications',
                style: TextStyle(color: Colors.white54),
              ),
            );
          }

          final docs = dedupeStreamRowsById(snap.data!);

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final data = docs[i];

              if (data['type'] == 'friend_request' &&
                  data['from_uid'] != null &&
                  data['request_id'] != null) {
                return _FriendRequestTile(
                  notificationId: data['id'] as String,
                  requestId: data['request_id'] as String,
                  fromUid: data['from_uid'] as String,
                );
              }

              if (data['type'] == 'club_request') {
                return _ClubRequestTile(
                  notificationId: data['id'] as String,
                  clubName: data['club_name'] ?? '',
                );
              }

              return const SizedBox.shrink();
            },
          );
        },
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

  const _ClubRequestTile({
    required this.notificationId,
    required this.clubName,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF1E1E22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'New Club Request',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              clubName.isEmpty
                  ? 'A student wants to start a club'
                  : '$clubName wants to join TrueKinn',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                    ),
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
                          const SnackBar(
                            content: Text('Could not dismiss. Try again.'),
                          ),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                    ),
                    child: const Text('Review'),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const AdminClubRequestsScreen(),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
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

  const _FriendRequestTile({
    required this.notificationId,
    required this.requestId,
    required this.fromUid,
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
          SnackBar(content: Text('Something went wrong: $e')),
        );
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF1E1E22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Friend Request',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                    ),
                    onPressed: _busy ? null : () => _respond(false),
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                    ),
                    onPressed: _busy ? null : () => _respond(true),
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white70,
                            ),
                          )
                        : const Text('Accept'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
