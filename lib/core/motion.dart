import 'package:flutter/material.dart';

/// TrueKinn's motion language, in one place so every screen picks from the
/// same small vocabulary instead of inventing new durations/curves.
///
/// Rule of thumb used throughout the app: state changes that are the
/// *result* of a tap (a like filling in, a button morphing, a sheet
/// opening) get [fast]/[base]; anything ambient or decorative (nothing
/// currently qualifies — we deliberately don't do ambient motion) would
/// get [slow]. Nothing in this app should run past [slow] — a "premium"
/// feel here means motion resolves before the user's finger has left the
/// glass, not a lingering animation.
class AppMotion {
  AppMotion._();

  static const Duration instant = Duration(milliseconds: 90);
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration base = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 320);

  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeOutExpo;
  static const Curve spring = Curves.easeOutBack;
}

/// True when the OS-level "reduce motion" accessibility setting is on.
/// Entrance/emphasis animations should check this and skip straight to
/// their end state rather than ignore it — real support, not a checkbox.
bool prefersReducedMotion(BuildContext context) {
  return MediaQuery.of(context).disableAnimations;
}
