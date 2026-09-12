import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FriendRequestTile extends StatelessWidget {
  final String requestId;
  final Map<String, dynamic> data;

  const FriendRequestTile({
    super.key,
    required this.requestId,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    final fromUid = data['fromUid'];

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(fromUid)
          .get(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const SizedBox.shrink();
        }

        final user = snap.data!.data() as Map<String, dynamic>;

        return ListTile(
          leading: CircleAvatar(
            backgroundImage: user['photoUrl'] != null
                ? NetworkImage(user['photoUrl'])
                : null,
            child: user['photoUrl'] == null
                ? const Icon(Icons.person)
                : null,
          ),
          title: Text(
            user['name'] ?? 'Unknown',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: const Text('sent you a friend request'),
          trailing: TextButton(
            child: const Text('Accept'),
            onPressed: () async {
              await _acceptRequest(fromUid);
            },
          ),
        );
      },
    );
  }

  Future<void> _acceptRequest(String fromUid) async {
    final batch = FirebaseFirestore.instance.batch();

    // 1️⃣ Mark request as accepted
    batch.update(
      FirebaseFirestore.instance
          .collection('friend_requests')
          .doc(requestId),
      {'status': 'accepted'},
    );

    // 2️⃣ Add each other as friends
    batch.set(
      FirebaseFirestore.instance
          .collection('friends')
          .doc('$fromUid'),
      {'uid': fromUid},
    );

    await batch.commit();
  }
}