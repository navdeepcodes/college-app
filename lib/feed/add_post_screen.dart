import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/storage_service.dart';
import '../auth/services/college_detector.dart';
import '../moderation/text_filter.dart';

class AddPostScreen extends StatefulWidget {
  const AddPostScreen({super.key});

  @override
  State<AddPostScreen> createState() => _AddPostScreenState();
}

class _AddPostScreenState extends State<AddPostScreen> {
  final _captionController = TextEditingController();
  File? _image;
  bool _loading = false;

  // ✅ CORRECT — no arguments
  final StorageService _storageService = StorageService();

  Future<void> _pickImage() async {
    final picked =
    await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => _image = File(picked.path));
    }
  }

  Future<void> _post() async {
    if (_image == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select an image')),
      );
      return;
    }

    // Moderation: block captions the content filter rejects (same policy as
    // the anonymous chat) BEFORE any upload or Firestore write.
    final caption = _captionController.text.trim();
    final captionFilter = TextFilter.filter(caption);
    if (!captionFilter.isAllowed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Caption blocked by filter')),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final postRef =
      FirebaseFirestore.instance.collection('posts').doc();

      // College identity for the isolated campus feed: the post carries the
      // owner's canonical collegeId, and the Firestore rule requires it to
      // match users/{uid}.collegeId on write and gates reads on it.
      final userSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final collegeId = canonicalCollegeId(userSnap.data());
      if (collegeId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Finish your profile to post to the campus feed'),
            ),
          );
        }
        return;
      }

      final mediaPath = await _storageService.uploadPostMedia(
        userId: uid,
        postId: postRef.id,
        file: _image!,
      );

      await postRef.set({
        'userId': uid,
        'collegeId': collegeId,
        'caption': captionFilter.cleanedText,
        'mediaPath': mediaPath,
        'createdAt': FieldValue.serverTimestamp(),
        'likesCount': 0,
        'commentsCount': 0,
      });

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({
        'postsCount': FieldValue.increment(1),
      });

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Post'),
        actions: [
          TextButton(
            onPressed: _loading ? null : _post,
            child: _loading
                ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : const Text('Post'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GestureDetector(
            onTap: _pickImage,
            child: Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(12),
              ),
              child: _image != null
                  ? ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  _image!,
                  fit: BoxFit.cover,
                  width: double.infinity,
                ),
              )
                  : const Center(
                child: Icon(Icons.add_a_photo, size: 40),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _captionController,
            decoration:
            const InputDecoration(hintText: 'Write a caption'),
            maxLines: null,
          ),
        ],
      ),
    );
  }
}