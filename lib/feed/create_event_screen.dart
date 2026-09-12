import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/storage_service.dart';

class CreateEventScreen extends StatefulWidget {
  const CreateEventScreen({super.key});

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();

  DateTime? _startDate;
  DateTime? _endDate;

  final List<File> _mediaFiles = [];
  bool _loading = false;

  late final StorageService _storageService;

  static const String _websiteBase =
      'https://demo.yourcollegeapp.com/events';

  @override
  void initState() {
    super.initState();
    // ✅ CORRECT
    _storageService = StorageService();
  }

  Future<void> _pickImages() async {
    final picked = await ImagePicker().pickMultiImage();
    if (picked.isNotEmpty) {
      setState(() {
        _mediaFiles.addAll(picked.map((e) => File(e.path)));
      });
    }
  }

  Future<void> _pickDate({required bool start}) async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime(2035),
      initialDate: DateTime.now(),
    );

    if (date != null) {
      setState(() {
        start ? _startDate = date : _endDate = date;
      });
    }
  }

  Future<void> _createEvent() async {
    if (_titleController.text.trim().isEmpty ||
        _descController.text.trim().isEmpty ||
        _startDate == null ||
        _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fill all required fields')),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final eventRef =
      FirebaseFirestore.instance.collection('events').doc();

      final eventLink = '$_websiteBase/${eventRef.id}';

      final List<String> mediaPaths = [];
      for (final file in _mediaFiles) {
        final path = await _storageService.uploadEventMedia(
          eventId: eventRef.id,
          file: file,
        );
        mediaPaths.add(path);
      }

      await eventRef.set({
        'title': _titleController.text.trim(),
        'description': _descController.text.trim(),
        'createdBy': uid,
        'mediaPaths': mediaPaths,
        'eventLink': eventLink,
        'startDate': Timestamp.fromDate(_startDate!),
        'endDate': Timestamp.fromDate(_endDate!),
        'createdAt': FieldValue.serverTimestamp(),
        'isActive': true,
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
        title: const Text('Create Event'),
        actions: [
          TextButton(
            onPressed: _loading ? null : _createEvent,
            child: _loading
                ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : const Text('Publish'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _field(_titleController, 'Event name'),
          const SizedBox(height: 12),
          _field(_descController, 'Event description', maxLines: 4),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _dateButton(
                  label: _startDate == null
                      ? 'Start date'
                      : _startDate!.toString().split(' ')[0],
                  onTap: () => _pickDate(start: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _dateButton(
                  label: _endDate == null
                      ? 'End date'
                      : _endDate!.toString().split(' ')[0],
                  onTap: () => _pickDate(start: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _pickImages,
            icon: const Icon(Icons.photo),
            label: const Text('Add event photos'),
          ),
          if (_mediaFiles.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '${_mediaFiles.length} photo(s) added',
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          const SizedBox(height: 24),
          Text(
            'Registration & payment handled on:\n$_websiteBase/{eventId}',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white54,
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String hint,
      {int maxLines = 1}) {
    return TextField(
      controller: c,
      maxLines: maxLines,
      decoration: InputDecoration(
        hintText: hint,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _dateButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return OutlinedButton(
      onPressed: onTap,
      child: Text(label),
    );
  }
}