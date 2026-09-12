import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MomentContext {
  final String uid;
  final String name;
  final String? photoUrl;
  final String college;

  MomentContext({
    required this.uid,
    required this.name,
    required this.college,
    this.photoUrl,
  });

  static Future<MomentContext?> load() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (!doc.exists || doc.data() == null) return null;

    final data = doc.data()!;

    if (data['college'] == null || data['name'] == null) return null;

    return MomentContext(
      uid: user.uid,
      name: data['name'],
      college: data['college'],
      photoUrl: data['photoUrl'],
    );
  }
}