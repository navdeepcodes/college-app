import 'package:flutter_test/flutter_test.dart';
import 'package:college_app/utils/dedupe_stream_rows.dart';

void main() {
  group('dedupeStreamRowsById', () {
    test('keeps a single row unchanged', () {
      final rows = [
        {'id': '1', 'text': 'hello'},
      ];
      expect(dedupeStreamRowsById(rows), rows);
    });

    test('drops a duplicate id, keeping the first occurrence', () {
      // Reproduces the exact race this guards against: Supabase's
      // SupabaseStreamBuilder appends every realtime INSERT unconditionally
      // (no primary-key check) while its own initial postgrest fetch can
      // independently already include that same row.
      final rows = [
        {'id': '1', 'text': 'hello'},
        {'id': '2', 'text': 'world'},
        {'id': '1', 'text': 'hello'},
      ];

      final result = dedupeStreamRowsById(rows);

      expect(result.length, 2);
      expect(result[0]['id'], '1');
      expect(result[1]['id'], '2');
    });

    test('preserves incoming order otherwise', () {
      final rows = [
        {'id': '3'},
        {'id': '1'},
        {'id': '2'},
      ];
      expect(
        dedupeStreamRowsById(rows).map((r) => r['id']).toList(),
        ['3', '1', '2'],
      );
    });

    test('returns an empty list for empty input', () {
      expect(dedupeStreamRowsById(const []), isEmpty);
    });

    test('supports a custom id key', () {
      final rows = [
        {'club_id': 'a'},
        {'club_id': 'b'},
        {'club_id': 'a'},
      ];
      expect(
        dedupeStreamRowsById(rows, idKey: 'club_id').length,
        2,
      );
    });
  });
}
