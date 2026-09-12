import 'package:cloud_firestore/cloud_firestore.dart';

class UserContext {
  static Future<String> getCollegeId(String uid) async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();

    return doc['collegeId'];
  }
}