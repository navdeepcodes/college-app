import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/friend_service.dart';

enum _Relationship { loading, friends, requestSent, requestReceived, none }

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
  final _firestore = FirebaseFirestore.instance;
  late final String _currentUid;

  _Relationship _relationship = _Relationship.loading;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _currentUid = FirebaseAuth.instance.currentUser!.uid;
    if (_currentUid != widget.targetUserId) {
      _loadRelationship();
    }
  }

  String get _pairId {
    final sorted = [_currentUid, widget.targetUserId]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  Future<void> _loadRelationship() async {
    bool alreadyFriends = false;
    try {
      final friendsDoc = await _firestore.collection('friends').doc(_pairId).get();
      alreadyFriends = friendsDoc.exists;
    } catch (_) {
      // See FriendService._areFriends: a nonexistent friends doc makes the
      // rules' resource.data dereference throw rather than returning
      // exists:false, so permission-denied here just means "not friends."
      alreadyFriends = false;
    }
    if (!mounted) return;

    if (alreadyFriends) {
      setState(() => _relationship = _Relationship.friends);
      return;
    }

    final outgoing = await _firestore
        .collection('friend_requests')
        .where('fromUid', isEqualTo: _currentUid)
        .where('toUid', isEqualTo: widget.targetUserId)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();
    if (!mounted) return;

    if (outgoing.docs.isNotEmpty) {
      setState(() => _relationship = _Relationship.requestSent);
      return;
    }

    final incoming = await _firestore
        .collection('friend_requests')
        .where('fromUid', isEqualTo: widget.targetUserId)
        .where('toUid', isEqualTo: _currentUid)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();
    if (!mounted) return;

    setState(() {
      _relationship = incoming.docs.isNotEmpty
          ? _Relationship.requestReceived
          : _Relationship.none;
    });
  }

  Future<void> _handleTap() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      // sendRequest already auto-accepts when the target already requested
      // us, so this single call correctly handles both the "none" and
      // "requestReceived" states.
      final result = await FriendService.sendRequest(
        fromUid: _currentUid,
        toUid: widget.targetUserId,
      );

      if (!mounted) return;

      switch (result) {
        case SendFriendRequestResult.sent:
          messenger.showSnackBar(
            const SnackBar(content: Text('Friend request sent')),
          );
          setState(() => _relationship = _Relationship.requestSent);
          break;
        case SendFriendRequestResult.acceptedIncoming:
          messenger.showSnackBar(
            const SnackBar(content: Text("You're now friends")),
          );
          setState(() => _relationship = _Relationship.friends);
          break;
        case SendFriendRequestResult.alreadyFriends:
          setState(() => _relationship = _Relationship.friends);
          break;
        case SendFriendRequestResult.alreadyPending:
          setState(() => _relationship = _Relationship.requestSent);
          break;
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Something went wrong: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUid == widget.targetUserId) {
      return const SizedBox.shrink();
    }

    if (_relationship == _Relationship.loading) {
      return const SizedBox(
        height: 36,
        width: 36,
        child: Padding(
          padding: EdgeInsets.all(8),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_relationship == _Relationship.friends) {
      return const Chip(
        avatar: Icon(Icons.check, size: 16),
        label: Text('Friends'),
      );
    }

    if (_relationship == _Relationship.requestSent) {
      return const OutlinedButton(
        onPressed: null,
        child: Text('Request Sent'),
      );
    }

    final label = _relationship == _Relationship.requestReceived
        ? 'Accept Request'
        : 'Add Friend';

    return ElevatedButton(
      onPressed: _busy ? null : _handleTap,
      child: _busy
          ? const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(label),
    );
  }
}
