import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../navigation/bottom_nav_shell.dart';
import '../../auth/services/college_detector.dart';

String generateAnonId() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final rand = Random.secure();
  return 'ANON-${List.generate(4, (_) => chars[rand.nextInt(chars.length)]).join()}';
}

class ProfileSetupPage extends StatefulWidget {
  const ProfileSetupPage({super.key});

  @override
  State<ProfileSetupPage> createState() => _ProfileSetupPageState();
}

class _ProfileSetupPageState extends State<ProfileSetupPage> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  SupabaseClient get _supabase => Supabase.instance.client;

  final _nameController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _bioController = TextEditingController();

  String? _college;
  String? _year;
  String? _branch;
  File? _image;

  bool _loading = false;

  final _years = const ['Fresher', 'Sophomore', 'Junior', 'Senior'];

  final _branches = const [
    'Computer Science Engineering (CSE)',
    'Information Science Engineering (ISE)',
    'Electronics & Communication Engineering (ECE)',
    'Electrical & Electronics Engineering (EEE)',
    'Mechanical Engineering (ME)',
    'Civil Engineering (CE)',
    'Aerospace Engineering',
    'Other',
  ];

  // ✅ ADD COLLEGE OPTIONS (minimal, logic-safe)
  final _colleges = const [
    'Nitte Meenakshi Institute of Technology',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final doc = await _firestore.collection('users').doc(user.uid).get();
    if (!mounted) return;

    final data = doc.data();
    setState(() {
      _nameController.text = data?['name'] ?? '';
      _nicknameController.text = data?['nickname'] ?? '';
      _bioController.text = data?['bio'] ?? '';
      _college = data?['college'];
      _year = data?['year'];
      _branch = data?['branch'];
    });
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => _image = File(picked.path));
    }
  }

  Future<void> _submit() async {
    final user = _auth.currentUser;
    if (user == null) return;

    if (_nameController.text.trim().isEmpty ||
        _college == null ||
        _year == null ||
        _branch == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete all required fields')),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      String? photoUrl;

      // ✅ upload ONLY if image selected
      if (_image != null) {
        final path = 'profiles/${user.uid}.jpg';
        await _supabase.storage
            .from('profile_photos')
            .upload(
          path,
          _image!,
          fileOptions: const FileOptions(upsert: true),
        );

        photoUrl = _supabase.storage
            .from('profile_photos')
            .getPublicUrl(path);
      }

      final userRef = _firestore.collection('users').doc(user.uid);

      final snap = await userRef.get();
      if (snap.data()?['anonId'] == null) {
        await userRef.set(
          {'anonId': generateAnonId()},
          SetOptions(merge: true),
        );
      }

      // ✅ build update map safely
      final updateData = {
        'uid': user.uid,
        'name': _nameController.text.trim(),
        'nickname': _nicknameController.text.trim(),
        'bio': _bioController.text.trim(),
        'college': _college,
        'collegeId': collegeIdForEmail(user.email, fallbackCollege: _college),
        'year': _year,
        'branch': _branch,
        'profileCompleted': true,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // ✅ do NOT overwrite existing photoUrl
      if (photoUrl != null) {
        updateData['photoUrl'] = photoUrl;
      }

      await userRef.set(updateData, SetOptions(merge: true));

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const BottomNavShell()),
            (_) => false,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set up your profile'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        children: [
          Center(
            child: GestureDetector(
              onTap: _pickImage,
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 58,
                    backgroundColor: Colors.white.withOpacity(0.08),
                    backgroundImage:
                    _image != null ? FileImage(_image!) : null,
                    child: _image == null
                        ? const Icon(Icons.camera_alt,
                        size: 30, color: Colors.white70)
                        : null,
                  ),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.deepPurple,
                    ),
                    child: const Icon(Icons.edit, size: 14),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 32),

          _editable(_nameController, 'Full Name'),
          const SizedBox(height: 14),
          _editable(_nicknameController, 'Nickname'),
          const SizedBox(height: 14),
          _editable(_bioController, 'Bio', maxLines: 2),

          const SizedBox(height: 20),

          _dropdown('College', _college, _colleges,
                  (v) => setState(() => _college = v)),
          const SizedBox(height: 14),
          _dropdown('Year', _year, _years,
                  (v) => setState(() => _year = v)),
          const SizedBox(height: 14),
          _dropdown('Branch', _branch, _branches,
                  (v) => setState(() => _branch = v)),

          const SizedBox(height: 36),

          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : const Text(
                'Continue',
                style:
                TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _editable(
      TextEditingController c,
      String label, {
        int maxLines = 1,
      }) {
    return TextField(
      controller: c,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }

  Widget _dropdown(
      String label,
      String? value,
      List<String> items,
      ValueChanged<String?> onChanged,
      ) {
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      items:
      items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }
}