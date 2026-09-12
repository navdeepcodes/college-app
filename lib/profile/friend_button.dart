import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/friend_service.dart';

class FriendButton extends StatefulWidget {
  final String targetUserId;

  const FriendButton({
    super.key,
    required this.targetUserId,
  });

  @override
  State<FriendButton> createState() => _FriendButtonState();
}

class _FriendButtonState extends State<FriendButton> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    // Safety: not logged in
    if (currentUid == null) {
      return const SizedBox.shrink();
    }

    // Do not show button on own profile
    if (currentUid == widget.targetUserId) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _loading
            ? null
            : () async {
          setState(() => _loading = true);

          await FriendService.sendRequest(
            fromUid: currentUid,
            toUid: widget.targetUserId,
          );

          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Friend request sent'),
            ),
          );

          setState(() => _loading = false);
        },
        child: _loading
            ? const SizedBox(
          height: 18,
          width: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
            : const Text('Add Friend'),
      ),
    );
  }
}