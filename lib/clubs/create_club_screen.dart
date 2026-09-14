import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
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

    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _loading = true);

    try {
      final filePath =
          'club_id_cards/${user.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';

      await supabase.storage.from('clubs').upload(filePath, _idCardImage!);

      // Stores the storage PATH, not a public URL: the clubs bucket is
      // private (ID card photos are personal documents, reviewed only by
      // platform admins), so admin_club_requests_screen.dart resolves this
      // into a short-lived signed URL on demand instead of rendering it
      // directly.
      final requestRow = await supabase
          .from('club_requests')
          .insert({
            'owner_uid': user.id,
            'club_name': _clubNameController.text.trim(),
            'description': _descriptionController.text.trim(),
            'phone': _phoneController.text.trim(),
            'usn': _usnController.text.trim(),
            'id_card_url': filePath,
          })
          .select()
          .single();

      // Recipient(s): whoever currently holds is_admin=true (see
      // admin_ids(), supabase/migrations/20260914000006_admin_lookup_rpc.sql
      // -- there's no compile-time admin UID equivalent to Firestore's
      // lib/core/admin.dart in Supabase's identity space). If no admin
      // account exists yet, there's simply nowhere to route the
      // notification -- skip rather than fail the whole request; the
      // club_request row itself is still there for an admin to find once
      // one exists.
      final adminIds = await supabase.rpc('admin_ids') as List<dynamic>;
      for (final adminId in adminIds) {
        await supabase.from('notifications').insert({
          'type': 'club_request',
          'request_id': requestRow['id'],
          'club_name': _clubNameController.text.trim(),
          'from_uid': user.id,
          'to_uid': adminId,
        });
      }

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
                      child: Image.file(_idCardImage!, fit: BoxFit.cover),
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
