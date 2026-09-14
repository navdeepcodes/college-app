import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/friend_service.dart';
import '../../core/app_colors.dart';
import '../../core/haptics.dart';
import '../../core/motion.dart';

enum _Relationship { loading, friends, requestSent, requestReceived, none, error }

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
    if (mounted) setState(() => _relationship = _Relationship.loading);
    try {
      final pair = _sortedPair;
      // A nonexistent friendship reads back as an empty list, not a thrown
      // error — no try/catch workaround needed for THAT here, unlike the
      // Firestore version (see FriendService._areFriends for the full
      // explanation). The try/catch here instead guards against a genuine
      // failure (network blip, RLS reject) leaving this stuck on the
      // loading spinner forever with no recovery — the exact bug class
      // found live in bottom_nav_shell.dart's null-user branch.
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
        _relationship = incoming.isNotEmpty
            ? _Relationship.requestReceived
            : _Relationship.none;
      });
    } catch (e) {
      debugPrint('FriendButton relationship load failed: $e');
      if (mounted) setState(() => _relationship = _Relationship.error);
    }
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
          AppHaptics.tap();
          messenger.showSnackBar(const SnackBar(content: Text('Friend request sent')));
          setState(() => _relationship = _Relationship.requestSent);
          break;
        case SendFriendRequestResult.acceptedIncoming:
          AppHaptics.confirm();
          messenger.showSnackBar(const SnackBar(content: Text("You're now friends")));
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
          const SnackBar(content: Text('Something went wrong. Try again.')),
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

    return AnimatedSwitcher(
      duration: AppMotion.base,
      switchInCurve: AppMotion.standard,
      switchOutCurve: AppMotion.standard,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(animation), child: child),
      ),
      child: KeyedSubtree(
        key: ValueKey(_relationship),
        child: _buildForState(),
      ),
    );
  }

  Widget _buildForState() {
    switch (_relationship) {
      case _Relationship.loading:
        return const SizedBox(
          height: 46,
          child: Center(
            child: SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );

      case _Relationship.error:
        return SizedBox(
          height: 46,
          child: OutlinedButton.icon(
            onPressed: _loadRelationship,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
          ),
        );

      case _Relationship.friends:
        return Container(
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(23),
            border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle_rounded, size: 18, color: AppColors.accentBright),
              SizedBox(width: 8),
              Text('Friends', style: TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        );

      case _Relationship.requestSent:
        return SizedBox(
          height: 46,
          child: OutlinedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.schedule_rounded, size: 17),
            label: const Text('Request sent'),
          ),
        );

      case _Relationship.requestReceived:
      case _Relationship.none:
        final label = _relationship == _Relationship.requestReceived ? 'Accept request' : 'Add friend';
        return SizedBox(
          height: 46,
          child: ElevatedButton.icon(
            onPressed: _busy ? null : _handleTap,
            icon: _busy
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Icon(
                    _relationship == _Relationship.requestReceived
                        ? Icons.check_rounded
                        : Icons.person_add_alt_1_rounded,
                    size: 18,
                  ),
            label: Text(label),
          ),
        );
    }
  }
}
