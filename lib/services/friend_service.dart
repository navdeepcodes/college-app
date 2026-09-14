import 'package:supabase_flutter/supabase_flutter.dart';

enum SendFriendRequestResult {
  sent,
  alreadyFriends,
  alreadyPending,
  acceptedIncoming,
}

class FriendService {
  static SupabaseClient get _db => Supabase.instance.client;

  static List<String> _sortedPair(String a, String b) => [a, b]..sort();

  static Future<bool> _areFriends(String a, String b) async {
    final pair = _sortedPair(a, b);
    final rows = await _db
        .from('friendships')
        .select('id')
        .eq('user_a', pair[0])
        .eq('user_b', pair[1])
        .limit(1);
    // Unlike the old Firestore version, a nonexistent friendship reads
    // back as an empty list here, not a thrown permission error -- see
    // docs/supabase-schema.md for why that whole bug class (three
    // separate incidents on the Firestore side) cannot recur in Postgres.
    return rows.isNotEmpty;
  }

  // ================= SEND REQUEST =================
  static Future<SendFriendRequestResult> sendRequest({
    required String fromUid,
    required String toUid,
  }) async {
    if (await _areFriends(fromUid, toUid)) {
      return SendFriendRequestResult.alreadyFriends;
    }

    final incoming = await _db
        .from('friend_requests')
        .select('id')
        .eq('from_uid', toUid)
        .eq('to_uid', fromUid)
        .eq('status', 'pending')
        .limit(1);

    if (incoming.isNotEmpty) {
      await acceptRequest(
        requestId: incoming.first['id'],
        fromUid: toUid,
        toUid: fromUid,
      );
      return SendFriendRequestResult.acceptedIncoming;
    }

    final existing = await _db
        .from('friend_requests')
        .select('id')
        .eq('from_uid', fromUid)
        .eq('to_uid', toUid)
        .eq('status', 'pending')
        .limit(1);

    if (existing.isNotEmpty) {
      return SendFriendRequestResult.alreadyPending;
    }

    final requestRow = await _db
        .from('friend_requests')
        .insert({'from_uid': fromUid, 'to_uid': toUid})
        .select()
        .single();

    await _db.from('notifications').insert({
      'type': 'friend_request',
      'request_id': requestRow['id'],
      'from_uid': fromUid,
      'to_uid': toUid,
    });

    return SendFriendRequestResult.sent;
  }

  // ================= ACCEPT REQUEST =================
  static Future<void> acceptRequest({
    required String requestId,
    required String fromUid,
    required String toUid,
  }) async {
    if (await _areFriends(fromUid, toUid)) {
      await _db.from('friend_requests').delete().eq('id', requestId);
      await _deleteRequestNotifications(requestId);
      return;
    }

    // Same ordering constraint as the Firestore version, now enforced by
    // the friendships_insert RLS policy directly (see
    // supabase/migrations/20260914000002_rls_policies.sql): the source
    // request must still be 'pending' at the moment the friendship row is
    // created. Create first, delete the request after.
    final pair = _sortedPair(fromUid, toUid);
    await _db.from('friendships').insert({
      'user_a': pair[0],
      'user_b': pair[1],
      'source_request_id': requestId,
    });

    // friends_count for both members is bumped by the
    // bump_friends_count trigger (database-side, not client-issued) --
    // see supabase/migrations/20260914000001_initial_schema.sql.

    await _db.from('friend_requests').delete().eq('id', requestId);
    await _deleteRequestNotifications(requestId);
  }

  // ================= DECLINE REQUEST =================
  static Future<void> declineRequest({required String requestId}) async {
    await _db.from('friend_requests').delete().eq('id', requestId);
    await _deleteRequestNotifications(requestId);
  }

  static Future<void> _deleteRequestNotifications(String requestId) async {
    await _db
        .from('notifications')
        .delete()
        .eq('type', 'friend_request')
        .eq('request_id', requestId);
  }
}
