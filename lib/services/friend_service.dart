import 'package:cloud_firestore/cloud_firestore.dart';

enum SendFriendRequestResult {
  sent,
  alreadyFriends,
  alreadyPending,
  acceptedIncoming,
}

class FriendService {
  static final _firestore = FirebaseFirestore.instance;

  /// Deterministic id for the `friends` edge between two users — order
  /// independent. Prevents concurrent/duplicate accepts from creating two
  /// friendship docs (and double-firing the friendCreated counter function):
  /// a second write to the same id is a rules `update`, and the friends
  /// collection denies all updates.
  static String _pairId(String a, String b) {
    final sorted = [a, b]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  static Future<bool> _areFriends(String a, String b) async {
    try {
      final doc = await _firestore.collection('friends').doc(_pairId(a, b)).get();
      return doc.exists;
    } catch (_) {
      // firestore.rules' friends.read dereferences resource.data to check
      // membership — for a pair that was never friends (the common case),
      // the doc doesn't exist, resource is null, and that dereference
      // throws rather than evaluating to false. get() on a nonexistent
      // friends doc therefore raises permission-denied instead of
      // returning exists:false. Both callers here only ever check a pair
      // that includes the caller, so any failure means "not friends."
      return false;
    }
  }

  // ================= SEND REQUEST =================
  /// Sends a friend request from [fromUid] to [toUid]. If [toUid] already
  /// sent [fromUid] a pending request, completes the friendship immediately
  /// instead of creating a second, crossed request (matches how every
  /// mainstream friend-request UI behaves, and avoids the duplicate-request
  /// state the old unconditional `add()` could create).
  static Future<SendFriendRequestResult> sendRequest({
    required String fromUid,
    required String toUid,
  }) async {
    if (await _areFriends(fromUid, toUid)) {
      return SendFriendRequestResult.alreadyFriends;
    }

    // Reverse-direction pending request: they already asked us.
    final incoming = await _firestore
        .collection('friend_requests')
        .where('fromUid', isEqualTo: toUid)
        .where('toUid', isEqualTo: fromUid)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();

    if (incoming.docs.isNotEmpty) {
      await acceptRequest(
        requestId: incoming.docs.first.id,
        fromUid: toUid,
        toUid: fromUid,
      );
      return SendFriendRequestResult.acceptedIncoming;
    }

    // Our own pending request, already sent.
    final existing = await _firestore
        .collection('friend_requests')
        .where('fromUid', isEqualTo: fromUid)
        .where('toUid', isEqualTo: toUid)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      return SendFriendRequestResult.alreadyPending;
    }

    final requestRef = await _firestore.collection('friend_requests').add({
      'fromUid': fromUid,
      'toUid': toUid,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Surface it: notifications_screen.dart's friend-request tile already
    // exists but was unreachable because nothing ever wrote this doc.
    await _firestore.collection('notifications').add({
      'type': 'friend_request',
      'requestId': requestRef.id,
      'fromUid': fromUid,
      'toUid': toUid,
      'createdAt': FieldValue.serverTimestamp(),
      'read': false,
    });

    return SendFriendRequestResult.sent;
  }

  // ================= ACCEPT REQUEST =================
  static Future<void> acceptRequest({
    required String requestId,
    required String fromUid,
    required String toUid,
  }) async {
    final requestRef = _firestore.collection('friend_requests').doc(requestId);

    if (await _areFriends(fromUid, toUid)) {
      // Already friends (e.g. both sides accepted concurrently) — just
      // clear the now-redundant request instead of a doomed rules-denied
      // write to an existing friends doc.
      await requestRef.delete();
      await _deleteRequestNotifications(requestId);
      return;
    }

    // Not a batch: the friends.create rule verifies sourceRequestId still
    // points at a *pending* friend_requests doc (consent check — see
    // firestore.rules), so the request must still exist at the moment the
    // friends doc is created. Deleting it first, or in the same batch where
    // ordering isn't guaranteed from the rule's point of view, would make
    // the create unverifiable. Create first, then clean up.
    final friendsRef = _firestore.collection('friends').doc(_pairId(fromUid, toUid));
    await friendsRef.set({
      'members': [fromUid, toUid],
      'sourceRequestId': requestId,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // friendsCount for BOTH members is bumped by the friendCreated Cloud
    // Function (functions/index.js) using the admin SDK. A client can only
    // write its OWN users doc, so incrementing the peer's counter here would
    // fail the owner-only users rule (firestore.rules users block).

    await requestRef.delete();
    await _deleteRequestNotifications(requestId);
  }

  // ================= DECLINE REQUEST =================
  static Future<void> declineRequest({required String requestId}) async {
    await _firestore.collection('friend_requests').doc(requestId).delete();
    await _deleteRequestNotifications(requestId);
  }

  static Future<void> _deleteRequestNotifications(String requestId) async {
    final notifs = await _firestore
        .collection('notifications')
        .where('type', isEqualTo: 'friend_request')
        .where('requestId', isEqualTo: requestId)
        .get();

    if (notifs.docs.isEmpty) return;

    final batch = _firestore.batch();
    for (final doc in notifs.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
}
