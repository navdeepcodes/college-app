import 'package:flutter_test/flutter_test.dart';
import 'package:college_app/core/widgets/relative_time.dart';

void main() {
  group('relativeTime', () {
    test('shows "Just now" for a few seconds ago', () {
      final t = DateTime.now().subtract(const Duration(seconds: 10));
      expect(relativeTime(t), 'Just now');
    });

    test('shows minutes for under an hour', () {
      final t = DateTime.now().subtract(const Duration(minutes: 5));
      expect(relativeTime(t), '5m ago');
    });

    test('shows hours for under a day', () {
      final t = DateTime.now().subtract(const Duration(hours: 3));
      expect(relativeTime(t), '3h ago');
    });

    test('shows days for under a week', () {
      final t = DateTime.now().subtract(const Duration(days: 2));
      expect(relativeTime(t), '2d ago');
    });

    test('shows weeks for under a month', () {
      final t = DateTime.now().subtract(const Duration(days: 14));
      expect(relativeTime(t), '2w ago');
    });

    test('shows a date for anything older', () {
      final t = DateTime.now().subtract(const Duration(days: 60));
      final result = relativeTime(t);
      expect(result, matches(RegExp(r'^\d{2}/\d{2}/\d{4}$')));
    });
  });
}
