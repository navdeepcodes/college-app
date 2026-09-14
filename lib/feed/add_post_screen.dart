import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
      final supabase = Supabase.instance.client;
      final uid = supabase.auth.currentUser!.id;

      final profileRows =
          await supabase.from('profiles').select().eq('id', uid).limit(1);
      final collegeId = profileRows.isNotEmpty
          ? canonicalCollegeId(profileRows.first)
          : '';
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
        postId: DateTime.now().millisecondsSinceEpoch.toString(),
        file: _image!,
      );

      await supabase.from('posts').insert({
        'user_id': uid,
        'college_id': collegeId,
        'text': captionFilter.cleanedText,
        'media_path': mediaPath,
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
            decoration: const InputDecoration(hintText: 'Write a caption'),
            maxLines: null,
          ),
        ],
      ),
    );
  }
}
