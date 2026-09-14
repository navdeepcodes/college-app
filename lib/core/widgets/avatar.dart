import 'package:flutter/material.dart';
import '../app_colors.dart';

/// A shared avatar treatment used everywhere a user's photo appears.
///
/// Replaces the app's inconsistent ad hoc `CircleAvatar`s (radius values
/// ranging 14–58 with no shared scale, and a generic gray person-icon
/// fallback that made every profile without a photo look like an empty
/// database row). Missing a photo now shows the person's own initial on a
/// deterministic color gradient — still clearly "this specific person,"
/// not a placeholder.
class AppAvatar extends StatelessWidget {
  final String? photoUrl;
  final String name;
  final double radius;
  final String? heroTag;
  final Border? ring;

  const AppAvatar({
    super.key,
    required this.photoUrl,
    required this.name,
    this.radius = 20,
    this.heroTag,
    this.ring,
  });

  String get _initial {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    final gradient = AppColors.avatarGradientFor(name.isEmpty ? '?' : name);

    Widget content;
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      content = ClipOval(
        child: Image.network(
          photoUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _initialCircle(gradient),
        ),
      );
    } else {
      content = _initialCircle(gradient);
    }

    final decorated = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, border: ring),
      child: content,
    );

    if (heroTag == null) return decorated;
    return Hero(tag: heroTag!, child: decorated);
  }

  Widget _initialCircle(List<Color> gradient) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Text(
        _initial,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.78,
        ),
      ),
    );
  }
}
