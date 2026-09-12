import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ClubJoinService {
  static final _firestore = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  // ================= REQUEST JOIN =================
  static Future<void> requestJoin({
    required String clubId,
    required String collegeId,
  }) async {
    final uid = _auth.currentUser!.uid;

    final existing = await _firestore
        .collection('club_join_requests')
        .where('clubId', isEqualTo: clubId)
        .where('userId', isEqualTo: uid)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) return;

    await _firestore.collection('club_join_requests').add({
      'clubId': clubId,
      'userId': uid,
      'collegeId': collegeId,
      'status': 'pending',
      'requestedAt': FieldValue.serverTimestamp(),
    });
  }

  // ================= REQUEST STATUS =================
  static Stream<String?> requestStatus(String clubId) {
    final uid = _auth.currentUser!.uid;

    return _firestore
        .collection('club_join_requests')
        .where('clubId', isEqualTo: clubId)
        .where('userId', isEqualTo: uid)
        .limit(1)
        .snapshots()
        .map((snap) {
      if (snap.docs.isEmpty) return null;
      return snap.docs.first['status'];
    });
  }

  // ================= IS MEMBER =================
  static Stream<bool> isMember(String clubId) {
    final uid = _auth.currentUser!.uid;

    return _firestore
        .collection('club_members')
        .where('clubId', isEqualTo: clubId)
        .where('userId', isEqualTo: uid)
        .limit(1)
        .snapshots()
        .map((snap) => snap.docs.isNotEmpty);
  }
}