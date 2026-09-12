import 'dart:math';

class PresenceService {
  PresenceService._();

  // =====================================================
  // PHASE 1 — ESTIMATED ONLINE COUNT (NO FIREBASE READS)
  // =====================================================

  static int estimateOnline({
    required int collegeBase,
    double growthFactor = 1.0,
  }) {
    final now = DateTime.now();
    final hour = now.hour;

    double multiplier;

    // 🧠 Human behaviour curve
    if (hour >= 8 && hour <= 11) {
      multiplier = 0.65;
    } else if (hour >= 12 && hour <= 14) {
      multiplier = 0.85;
    } else if (hour >= 15 && hour <= 18) {
      multiplier = 0.75;
    } else if (hour >= 19 && hour <= 23) {
      multiplier = 0.5; // 🔥 peak time
    } else {
      multiplier = 0.35; // late night
    }

    final base = (collegeBase * multiplier * growthFactor).round();

    // 🎲 Small randomness so number feels "alive"
    final variance = max(1, (base * 0.08).round());
    final randomOffset = Random().nextInt(variance);

    return base + randomOffset;
  }

  // =====================================================
  // FORMAT NUMBER (3.4k, 1.2k etc.)
  // =====================================================

  static String format(int count) {
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}k';
    }
    return count.toString();
  }
}