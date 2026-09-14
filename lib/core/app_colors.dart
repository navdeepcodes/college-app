import 'package:flutter/material.dart';

/// TrueKinn's design tokens. Everything here is a deliberate choice, not a
/// Material default — treat this file as the single source of truth for
/// color; screens should reference these tokens (or Theme.of(context))
/// rather than hardcoding Colors.* / Color(0xFF...) inline.
///
/// Direction: "after-hours campus" — a warm, close, slightly nocturnal
/// palette (near-black canvas, one confident violet accent) rather than a
/// clinical white social-app look or a flat corporate dark mode. This is
/// the same territory the pre-existing anon-chat screen was already
/// reaching for (radial purple glow on black); the rest of the app is
/// brought up to meet it, not the other way around.
class AppColors {
  AppColors._();

  // ================= BRAND =================
  // A touch more saturated / blue-leaning than the old flat #6A3DE8 so it
  // reads as chosen rather than "the default Flutter deepPurple."
  static const Color accent = Color(0xFF7C5CFF);
  static const Color accentBright = Color(0xFFB18CFF);
  static const Color accentDeep = Color(0xFF4B33A8);

  static const List<Color> accentGradient = [accentBright, accent, accentDeep];
  static const List<Color> accentGradientSoft = [Color(0xFF8B6BFF), Color(0xFF5B3FD1)];

  // ================= SURFACES =================
  // Near-black with a faint blue-violet undertone, not pure #000 — pure
  // black reads flat/cheap on OLED and fights the violet accent; a hair of
  // hue keeps the whole palette cohesive.
  static const Color background = Color(0xFF0A0A10);
  static const Color surface = Color(0xFF141319);
  static const Color surfaceRaised = Color(0xFF1B1A22);
  static const Color surfaceSunken = Color(0xFF0F0E14);
  static const Color surfaceOverlay = Color(0xF2121118); // dialogs/sheets

  // ================= TEXT =================
  static const Color textPrimary = Color(0xFFF3F2F8);
  static const Color textSecondary = Color(0xFFAFACC0);
  static const Color textMuted = Color(0xFF716D82);

  // ================= BORDERS =================
  static const Color border = Color(0xFF262433);
  static const Color borderStrong = Color(0xFF37344A);

  // ================= STATUS =================
  static const Color success = Color(0xFF34D399);
  static const Color danger = Color(0xFFFB6767);
  static const Color warning = Color(0xFFF7B95E);

  static const Color successBg = Color(0xFF16281F);
  static const Color dangerBg = Color(0xFF2E1717);
  static const Color warningBg = Color(0xFF2E2313);

  // ================= ANONYMOUS MODE =================
  // Its own slightly cooler / moodier accent so "shadow mode" keeps a
  // distinct identity from the rest of the app, while still sharing the
  // same violet family (not a clashing second brand color).
  static const Color anonAccent = Color(0xFF9B7BFF);
  static const List<Color> anonBackdrop = [Color(0xFF1A1730), Color(0xFF0A0A10)];

  /// Deterministic accent-family gradient for avatar-initial fallbacks, so
  /// two different users get visibly different but still on-brand colors
  /// instead of one flat generic gray circle.
  static List<Color> avatarGradientFor(String seed) {
    final palettes = <List<Color>>[
      [const Color(0xFF8B6BFF), const Color(0xFF4B33A8)],
      [const Color(0xFFFF8FB1), const Color(0xFFB1409A)],
      [const Color(0xFF67D6C4), const Color(0xFF2C8E8E)],
      [const Color(0xFFFFB067), const Color(0xFFB1602C)],
      [const Color(0xFF7BA9FF), const Color(0xFF3557B1)],
      [const Color(0xFFFF8F6B), const Color(0xFFB14C2C)],
    ];
    var hash = 0;
    for (final unit in seed.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return palettes[hash % palettes.length];
  }
}
