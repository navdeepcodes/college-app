import 'package:flutter/material.dart';
import '../app_colors.dart';

/// A loading placeholder with a soft sweeping shine — built on plain
/// Flutter (AnimationController + ShaderMask), no `shimmer` package. Used
/// wherever a fixed-shape piece of content is about to appear (a post
/// image, a club card, an avatar) so the screen reads as "loading this
/// specific thing" rather than a generic spinner floating in empty space.
class Skeleton extends StatefulWidget {
  final double? width;
  final double? height;
  final BorderRadius borderRadius;

  const Skeleton({
    super.key,
    this.width,
    this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return ShaderMask(
              shaderCallback: (rect) {
                final t = _controller.value;
                return LinearGradient(
                  begin: Alignment(-1 - t * 3, 0),
                  end: Alignment(1 - t * 3, 0),
                  colors: const [
                    AppColors.surfaceSunken,
                    AppColors.surfaceRaised,
                    AppColors.surfaceSunken,
                  ],
                  stops: const [0.35, 0.5, 0.65],
                ).createShader(rect);
              },
              child: Container(color: AppColors.surfaceSunken),
            );
          },
        ),
      ),
    );
  }
}
