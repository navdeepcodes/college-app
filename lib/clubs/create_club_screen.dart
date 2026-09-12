import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CreateClubScreen extends StatefulWidget {
  const CreateClubScreen({super.key});

  @override
  State<CreateClubScreen> createState() => _CreateClubScreenState();
}

class _CreateClubScreenState extends State<CreateClubScreen> {
  final _clubNameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _phoneController = TextEditingController();
  final _usnController = TextEditingController();

  File? _idCardImage;
  bool _loading = false;

  Future<void> _pickIdCard() async {
    final picked =
    await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => _idCardImage = File(picked.path));
    }
  }

  Future<void> _submitRequest() async {
    if (_idCardImage == null ||
        _clubNameController.text.isEmpty ||
        _descriptionController.text.isEmpty ||
        _phoneController.text.isEmpty ||
        _usnController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields')),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _loading = true);

    try {
      // ✅ CORRECT & SAFE
      final supabase = Supabase.instance.client;

      final filePath =
          'club_id_cards/${user.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg';

      await supabase.storage.from('clubs').upload(
        filePath,
        _idCardImage!,
      );

      final idCardUrl =
      supabase.storage.from('clubs').getPublicUrl(filePath);

      final requestRef =
      await FirebaseFirestore.instance.collection('club_requests').add({
        'ownerUid': user.uid,
        'clubName': _clubNameController.text.trim(),
        'description': _descriptionController.text.trim(),
        'phone': _phoneController.text.trim(),
        'usn': _usnController.text.trim(),
        'idCardUrl': idCardUrl,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      await FirebaseFirestore.instance.collection('notifications').add({
        'type': 'club_request',
        'requestId': requestRef.id,
        'clubName': _clubNameController.text.trim(),
        'fromUid': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'read': false,
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
      appBar: AppBar(title: const Text('Create Club')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _input('Club Name', _clubNameController),
          _input('What is this club for?', _descriptionController,
              maxLines: 3),
          _input('Mobile Number', _phoneController,
              keyboard: TextInputType.phone),
          _input('USN', _usnController),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _pickIdCard,
            child: Container(
              height: 160,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Colors.white.withAlpha(20),
              ),
              child: _idCardImage != null
                  ? ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child:
                Image.file(_idCardImage!, fit: BoxFit.cover),
              )
                  : const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.upload_file, size: 40),
                    SizedBox(height: 8),
                    Text('Upload College ID Card'),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loading ? null : _submitRequest,
            child: _loading
                ? const CircularProgressIndicator()
                : const Text('Submit for Approval'),
          ),
        ],
      ),
    );
  }

  Widget _input(
      String hint,
      TextEditingController controller, {
        int maxLines = 1,
        TextInputType keyboard = TextInputType.text,
      }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboard,
        decoration: InputDecoration(hintText: hint),
      ),
    );
  }
}