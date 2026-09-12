import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:college_app/services/storage_service.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _nicknameController = TextEditingController();
  final _bioController = TextEditingController();

  File? _image;
  bool _loading = false;

  // ✅ StorageService is stateless → no constructor needed
  final StorageService _storageService = StorageService();

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final doc =
    await FirebaseFirestore.instance.collection('users').doc(uid).get();

    if (!mounted) return;

    final data = doc.data();
    if (data == null) return;

    _nicknameController.text = data['nickname'] ?? '';
    _bioController.text = data['bio'] ?? '';
  }

  Future<void> _pickImage() async {
    final picked =
    await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => _image = File(picked.path));
    }
  }

  Future<void> _save() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    setState(() => _loading = true);

    try {
      String? photoUrl;

      if (_image != null) {
        photoUrl = await _storageService.uploadProfileImage(
          userId: uid,
          file: _image!,
        );
      }

      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'nickname': _nicknameController.text.trim().isEmpty
            ? null
            : _nicknameController.text.trim(),
        'bio': _bioController.text.trim().isEmpty
            ? null
            : _bioController.text.trim(),
        if (photoUrl != null) 'photoUrl': photoUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save profile: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        actions: [
          TextButton(
            onPressed: _loading ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 12),
          Center(
            child: GestureDetector(
              onTap: _pickImage,
              child: CircleAvatar(
                radius: 54,
                backgroundColor: Colors.grey.shade900,
                backgroundImage:
                _image != null ? FileImage(_image!) : null,
                child: _image == null
                    ? const Icon(
                  Icons.camera_alt,
                  size: 28,
                  color: Colors.white70,
                )
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _nicknameController,
            decoration: const InputDecoration(
              labelText: 'Nickname',
              hintText: 'e.g. deepcn',
              filled: true,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _bioController,
            maxLines: 3,
            maxLength: 150,
            decoration: const InputDecoration(
              labelText: 'Bio',
              hintText: 'Tell something about yourself',
              filled: true,
            ),
          ),
        ],
      ),
    );
  }
}