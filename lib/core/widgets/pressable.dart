import 'package:flutter/material.dart';
import '../motion.dart';

/// A tap target that visibly compresses on press and springs back on
/// release — for the app's many custom `GestureDetector`-wrapped
/// containers (club cards, chat send buttons, pill CTAs) that previously
/// had zero press feedback of any kind. Standard Material widgets
/// (ElevatedButton, InkWell, IconButton) already get a ripple for free and
/// don't need this.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;
  final BorderRadius? borderRadius;

  const Pressable({
    super.key,
    required this.child,
    required this.onTap,
    this.pressedScale = 0.96,
    this.borderRadius,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onTap == null) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: AppMotion.instant,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
