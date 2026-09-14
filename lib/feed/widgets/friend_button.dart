import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  SupabaseClient get _db => Supabase.instance.client;
  late final String _currentUid;

  _Relationship _relationship = _Relationship.loading;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _currentUid = Supabase.instance.client.auth.currentUser!.id;
    if (_currentUid != widget.targetUserId) {
      _loadRelationship();
    }
  }

  List<String> get _sortedPair => [_currentUid, widget.targetUserId]..sort();

  Future<void> _loadRelationship() async {
    final pair = _sortedPair;
    // A nonexistent friendship reads back as an empty list, not a thrown
    // error — no try/catch workaround needed here, unlike the Firestore
    // version (see FriendService._areFriends for the full explanation).
    final friendsRows = await _db
        .from('friendships')
        .select('id')
        .eq('user_a', pair[0])
        .eq('user_b', pair[1])
        .limit(1);
    if (!mounted) return;

    if (friendsRows.isNotEmpty) {
      setState(() => _relationship = _Relationship.friends);
      return;
    }

    final outgoing = await _db
        .from('friend_requests')
        .select('id')
        .eq('from_uid', _currentUid)
        .eq('to_uid', widget.targetUserId)
        .eq('status', 'pending')
        .limit(1);
    if (!mounted) return;

    if (outgoing.isNotEmpty) {
      setState(() => _relationship = _Relationship.requestSent);
      return;
    }

    final incoming = await _db
        .from('friend_requests')
        .select('id')
        .eq('from_uid', widget.targetUserId)
        .eq('to_uid', _currentUid)
        .eq('status', 'pending')
        .limit(1);
    if (!mounted) return;

    setState(() {
      _relationship =
          incoming.isNotEmpty ? _Relationship.requestReceived : _Relationship.none;
    });
  }

  Future<void> _handleTap() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
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
