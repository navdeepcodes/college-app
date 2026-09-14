import 'package:flutter/material.dart';
import '../motion.dart';

/// Animates its child in once, the first time a widget with this [key]
/// enters the tree — then never again.
///
/// The app's lists are almost all StreamBuilder-driven, which rebuilds the
/// *entire* list on every emission. Naively animating every build would
/// mean already-visible rows re-animate every time someone else's like
/// lands. Instead: wrap each row in `Entrance(key: ValueKey(id), ...)`.
/// Flutter's element diffing preserves State for a key it has already
/// seen, so an existing row's State (and its "already played" flag) lives
/// on across rebuilds — only a row with a genuinely new key gets a fresh
/// State, and therefore a fresh entrance animation. This is the standard
/// Flutter mechanism for "animate new items only," not a special trick.
class Entrance extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Duration delay;
  final Offset offset;

  const Entrance({
    super.key,
    required this.child,
    this.duration = AppMotion.base,
    this.delay = Duration.zero,
    this.offset = const Offset(0, 0.06),
  });

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  bool _skip = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _fade = CurvedAnimation(parent: _controller, curve: AppMotion.standard);
    _slide = Tween<Offset>(begin: widget.offset, end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: AppMotion.standard));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery.of() can only be read once this element is actually
    // attached to the tree, which isn't guaranteed yet inside initState —
    // reading it there throws in debug builds. didChangeDependencies is
    // the correct place, but it can fire more than once (e.g. a theme
    // change), so a start-once guard keeps the animation from replaying.
    if (_started) return;
    _started = true;

    _skip = prefersReducedMotion(context);
    if (_skip) {
      _controller.value = 1;
    } else if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_skip) return widget.child;
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
