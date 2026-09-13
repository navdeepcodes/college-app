import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../clubs/admin_club_requests_screen.dart';
import '../services/friend_service.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    // Prevent Android auth race condition
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

    final uid = user.uid;

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
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('notifications')
            .where('toUid', isEqualTo: uid)
            .orderBy('createdAt', descending: true)
            .limit(100)
            .snapshots(),
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

          if (!snap.hasData || snap.data!.docs.isEmpty) {
            return const Center(
              child: Text(
                'No notifications',
                style: TextStyle(color: Colors.white54),
              ),
            );
          }

          final docs = snap.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final data = docs[i].data() as Map<String, dynamic>;

              if (data['type'] == 'friend_request' &&
                  data['fromUid'] != null &&
                  data['requestId'] != null) {
                return _FriendRequestTile(
                  notificationId: docs[i].id,
                  requestId: data['requestId'],
                  fromUid: data['fromUid'],
                );
              }

              if (data['type'] == 'club_request') {
                return _ClubRequestTile(
                  notificationId: docs[i].id,
                  clubName: data['clubName'] ?? '',
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
                      await FirebaseFirestore.instance
                          .collection('notifications')
                          .doc(notificationId)
                          .delete();
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
      final myUid = FirebaseAuth.instance.currentUser!.uid;
      if (accept) {
        await FriendService.acceptRequest(
          requestId: widget.requestId,
          fromUid: widget.fromUid,
          toUid: myUid,
        );
      } else {
        await FriendService.declineRequest(requestId: widget.requestId);
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Something went wrong: $e')),
        );
        setState(() => _busy = false);
      }
    }
    // On success FriendService already deletes the notification doc (via
    // _deleteRequestNotifications), so this tile disappears with the stream
    // update — no need to reset _busy or delete it again here.
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