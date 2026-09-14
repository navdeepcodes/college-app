import 'package:supabase_flutter/supabase_flutter.dart';

/// Minimum viable moderation surface (hardening pass task I): report a
/// piece of content or a user, and block a user. Authorization for all of
/// this lives entirely in RLS (supabase/migrations/20260914000017_..., 018)
/// -- this service is a thin client wrapper, not where the security
/// boundary is.
class ModerationService {
  static SupabaseClient get _db => Supabase.instance.client;

  /// Files a report. `targetType` must match the reports.target_type check
  /// constraint: post, comment, message, club_message, user, anon_message.
  /// Throws on failure -- including the expected case of reporting the same
  /// target twice (unique constraint), which callers should catch and show
  /// as "You already reported this" rather than a generic error.
  static Future<void> report({
    required String targetType,
    required String targetId,
    required String reason,
    String? details,
  }) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) throw StateError('Not signed in');

    await _db.from('reports').insert({
      'reporter_uid': uid,
      'target_type': targetType,
      'target_id': targetId,
      'reason': reason,
      if (details != null && details.trim().isNotEmpty)
        'details': details.trim(),
    });
  }

  static Future<void> blockUser(String userId) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) throw StateError('Not signed in');

    await _db.from('blocks').insert({
      'blocker_uid': uid,
      'blocked_uid': userId,
    });
  }

  static Future<void> unblockUser(String userId) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) throw StateError('Not signed in');

    await _db
        .from('blocks')
        .delete()
        .eq('blocker_uid', uid)
        .eq('blocked_uid', userId);
  }

  static Future<bool> hasBlocked(String userId) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return false;

    final rows = await _db
        .from('blocks')
        .select('id')
        .eq('blocker_uid', uid)
        .eq('blocked_uid', userId)
        .limit(1);
    return rows.isNotEmpty;
  }
}
