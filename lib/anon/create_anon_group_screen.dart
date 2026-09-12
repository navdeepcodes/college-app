import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CreateAnonGroupScreen extends StatefulWidget {
  const CreateAnonGroupScreen({super.key});

  @override
  State<CreateAnonGroupScreen> createState() => _CreateAnonGroupScreenState();
}

class _CreateAnonGroupScreenState extends State<CreateAnonGroupScreen> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();

  bool _loading = false;

  Future<void> _createGroup() async {
    if (_nameController.text.trim().isEmpty) return;

    setState(() => _loading = true);

    final user = FirebaseAuth.instance.currentUser!;
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    final collegeId = userDoc['collegeId'];

    await FirebaseFirestore.instance.collection('anon_groups').add({
      'name': _nameController.text.trim(),
      'description': _descController.text.trim(),
      'collegeId': collegeId,
      'createdBy': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });

    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Create Anon Group')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Group name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loading ? null : _createGroup,
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }
}