/// Supabase's `SupabaseStreamBuilder` appends every realtime INSERT event to
/// its buffered row list unconditionally (no primary-key check), while its
/// own initial postgrest fetch can independently already include that same
/// row -- if the INSERT event for a just-written row arrives after the
/// initial fetch has already resolved with it included, the row renders
/// twice. First found and fixed inline in
/// lib/anon/college_anon_chat_screen.dart (a real, live-reproduced
/// duplicate-message bug); this is that same fix, shared, so every other
/// `.stream()` consumer can apply it consistently instead of re-deriving it.
///
/// Call right after `snapshot.data!` in a StreamBuilder, before handing the
/// list to a ListView/grid. Keeps the first occurrence of each id and
/// preserves the incoming order otherwise.
List<Map<String, dynamic>> dedupeStreamRowsById(
  List<Map<String, dynamic>> rows, {
  String idKey = 'id',
}) {
  final seen = <Object?>{};
  return rows.where((row) => seen.add(row[idKey])).toList();
}
