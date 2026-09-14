import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../haptics.dart';

/// A like control shared between the feed and post detail screen.
///
/// The underlying mutation is still a real round trip to `post_likes` (see
/// FeedScreen._toggleLike) — this widget just stops making the user wait
/// for it to *see* a response: the icon flips and the count adjusts the
/// instant they tap, with a small bounce and a haptic tick, then quietly
/// reconciles with the authoritative Realtime value once it arrives. If
/// the mutation actually fails, it reverts and the caller's own snackbar
/// explains why — this widget never claims success on its own.
class LikeButton extends StatefulWidget {
  final bool isLiked;
  final int count;
  final Future<void> Function() onToggle;

  const LikeButton({
    super.key,
    required this.isLiked,
    required this.count,
    required this.onToggle,
  });

  @override
  State<LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<LikeButton> with SingleTickerProviderStateMixin {
  bool? _optimistic;
  bool _busy = false;
  late final AnimationController _bounce;
  late final Animation<double> _scale;

  bool get _liked => _optimistic ?? widget.isLiked;

  int get _displayCount {
    if (widget.isLiked == _liked) return widget.count;
    return widget.count + (_liked ? 1 : -1);
  }

  @override
  void initState() {
    super.initState();
    _bounce = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.35).chain(CurveTween(curve: Curves.easeOut)), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.35, end: 1.0).chain(CurveTween(curve: Curves.easeIn)), weight: 60),
    ]).animate(_bounce);
  }

  @override
  void didUpdateWidget(covariant LikeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_optimistic != null && widget.isLiked == _optimistic) {
      _optimistic = null;
    }
  }

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (_busy) return;
    final next = !_liked;
    setState(() {
      _optimistic = next;
      _busy = true;
    });
    if (next) {
      AppHaptics.tap();
      _bounce.forward(from: 0);
    }
    try {
      await widget.onToggle();
    } catch (_) {
      if (mounted) setState(() => _optimistic = !next);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final liked = _liked;
    return InkWell(
      onTap: _handleTap,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: _scale,
              child: Icon(
                liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                size: 22,
                color: liked ? AppColors.danger : AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$_displayCount',
              style: TextStyle(
                color: liked ? AppColors.danger : AppColors.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
