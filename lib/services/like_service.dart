import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LikeService {
  static final _firestore = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  static Future<void> toggleLike(String postId) async {
    final uid = _auth.currentUser!.uid;
    final postRef = _firestore.collection('posts').doc(postId);
    final likeRef = postRef.collection('likes').doc(uid);

    final likeSnap = await likeRef.get();

    if (likeSnap.exists) {
      // UNLIKE
      await likeRef.delete();
      await postRef.update({
        'likesCount': FieldValue.increment(-1),
      });
    } else {
      // LIKE
      await likeRef.set({
        'likedAt': FieldValue.serverTimestamp(),
      });
      await postRef.update({
        'likesCount': FieldValue.increment(1),
      });
    }
  }

  static Stream<bool> isLikedStream(String postId) {
    final uid = _auth.currentUser!.uid;
    return _firestore
        .collection('posts')
        .doc(postId)
        .collection('likes')
        .doc(uid)
        .snapshots()
        .map((doc) => doc.exists);
  }
}