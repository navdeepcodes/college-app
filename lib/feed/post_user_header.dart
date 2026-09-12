import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PostUserHeader extends StatelessWidget {
  final String userId;
  final VoidCallback? onTap;
  final Widget? trailing;

  const PostUserHeader({
    super.key,
    required this.userId,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || !snap.data!.exists) {
          return const SizedBox(height: 48);
        }

        final user = snap.data!.data() as Map<String, dynamic>;
        final name = user['name'] ?? 'User';
        final photoUrl = user['photoUrl'];

        return InkWell(
          onTap: onTap,
          child: Padding(
            padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundImage:
                  photoUrl != null ? NetworkImage(photoUrl) : null,
                  child: photoUrl == null
                      ? const Icon(Icons.person, size: 18)
                      : null,
                ),
                const SizedBox(width: 8),
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (trailing != null) trailing!,
              ],
            ),
          ),
        );
      },
    );
  }
}