import 'package:cloud_firestore/cloud_firestore.dart';

class FriendService {
  static final _firestore = FirebaseFirestore.instance;

  // ================= SEND REQUEST =================
  static Future<void> sendRequest({
    required String fromUid,
    required String toUid,
  }) async {
    // prevent duplicates
    final existing = await _firestore
        .collection('friend_requests')
        .where('fromUid', isEqualTo: fromUid)
        .where('toUid', isEqualTo: toUid)
        .where('status', isEqualTo: 'pending')
        .get();

    if (existing.docs.isNotEmpty) return;

    await _firestore.collection('friend_requests').add({
      'fromUid': fromUid,
      'toUid': toUid,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ================= ACCEPT REQUEST =================
  static Future<void> acceptRequest({
    required String requestId,
    required String fromUid,
    required String toUid,
  }) async {
    final batch = _firestore.batch();

    // 1️⃣ Create friendship
    final friendsRef = _firestore.collection('friends').doc();
    batch.set(friendsRef, {
      'members': [fromUid, toUid],
      'createdAt': FieldValue.serverTimestamp(),
    });

    // 2️⃣ Update counters
    batch.update(
      _firestore.collection('users').doc(fromUid),
      {'friendsCount': FieldValue.increment(1)},
    );

    batch.update(
      _firestore.collection('users').doc(toUid),
      {'friendsCount': FieldValue.increment(1)},
    );

    // 3️⃣ Delete request
    batch.delete(
      _firestore.collection('friend_requests').doc(requestId),
    );

    await batch.commit();
  }
}