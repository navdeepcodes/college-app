import 'package:flutter/services.dart';

/// Named, semantic haptic calls so call sites read as intent ("this was a
/// positive confirmation") rather than a raw impact level. Deliberately
/// small — every candidate below was chosen because it confirms a result
/// the user just caused, not because "haptics are premium." Passive
/// navigation (opening a screen, scrolling, switching feed tabs) gets none.
///
/// HapticFeedback's platform channel calls are already safe no-ops on
/// platforms/devices without haptic hardware, so no availability checks
/// are needed here.
class AppHaptics {
  AppHaptics._();

  /// A light UI selection: bottom-nav tab change, segmented control switch.
  static void select() => HapticFeedback.selectionClick();

  /// A small positive confirmation: like, friend request sent/accepted,
  /// join request sent, message sent.
  static void tap() => HapticFeedback.lightImpact();

  /// A completed, slightly weightier action: report submitted, club
  /// request approved/rejected, join request approved.
  static void confirm() => HapticFeedback.mediumImpact();

  /// A destructive or hard-to-undo action: blocking a user.
  static void warn() => HapticFeedback.heavyImpact();
}
