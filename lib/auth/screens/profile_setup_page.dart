import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../navigation/bottom_nav_shell.dart';
import '../../auth/services/college_detector.dart';
import '../../core/app_colors.dart';
import '../../core/haptics.dart';
import '../../core/spacing.dart';
import '../../core/widgets/entrance.dart';

class ProfileSetupPage extends StatefulWidget {
  const ProfileSetupPage({super.key});

  @override
  State<ProfileSetupPage> createState() => _ProfileSetupPageState();
}

class _ProfileSetupPageState extends State<ProfileSetupPage> {
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

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    final rows = await _supabase.from('profiles').select().eq('id', user.id).limit(1);
    if (!mounted) return;

    final data = rows.isNotEmpty ? rows.first : null;
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
    final user = _supabase.auth.currentUser;
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

      if (_image != null) {
        final path = 'profiles/${user.id}.jpg';
        await _supabase.storage.from('profile_photos').upload(
              path,
              _image!,
              fileOptions: const FileOptions(upsert: true),
            );

        photoUrl = _supabase.storage.from('profile_photos').getPublicUrl(path);
      }

      // Heal path for pre-bootstrap rows: mint anon_id once if missing.
      // (New users get it stamped at profile-row creation; the
      // enforce_profile_immutability trigger permits the first mint and
      // locks the value afterwards — see supabase/migrations/....sql.)
      final existing = await _supabase.from('profiles').select('anon_id').eq('id', user.id).limit(1);
      if (existing.isNotEmpty && existing.first['anon_id'] == null) {
        await _supabase.from('profiles').update({'anon_id': anonDisplayId()}).eq('id', user.id);
      }

      final updateData = <String, dynamic>{
        'name': _nameController.text.trim(),
        'nickname': _nicknameController.text.trim(),
        'bio': _bioController.text.trim(),
        'college': _college,
        'college_id': collegeIdForEmail(user.email, fallbackCollege: _college),
        'year': _year,
        'branch': _branch,
        'profile_completed': true,
      };

      if (photoUrl != null) {
        updateData['photo_url'] = photoUrl;
      }

      await _supabase.from('profiles').update(updateData).eq('id', user.id);

      if (!mounted) return;

      AppHaptics.confirm();

      // A single deliberate "graduation" moment — the one custom page
      // transition in the app — rather than the default instant cut, for
      // the exact instant a new user's profile becomes real.
      Navigator.pushAndRemoveUntil(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 480),
          pageBuilder: (_, __, ___) => const BottomNavShell(),
          transitionsBuilder: (_, animation, __, child) {
            final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
            return FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween(begin: 0.96, end: 1.0).animate(curved),
                child: child,
              ),
            );
          },
        ),
        (_) => false,
      );
    } catch (e) {
      debugPrint('Profile setup failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save your profile. Try again.'),
          ),
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
        title: const Text('Set up your profile'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.xl, AppSpace.xxl, AppSpace.xl, AppSpace.xxxl,
        ),
        children: [
          Entrance(
            child: Center(
              child: GestureDetector(
                onTap: _pickImage,
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    CircleAvatar(
                      radius: 56,
                      backgroundColor: AppColors.surfaceSunken,
                      backgroundImage: _image != null ? FileImage(_image!) : null,
                      child: _image == null
                          ? const Icon(Icons.add_a_photo_outlined, size: 26, color: AppColors.textSecondary)
                          : null,
                    ),
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.accent,
                        border: Border.all(color: AppColors.background, width: 2),
                      ),
                      child: const Icon(Icons.edit, size: 14, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          Entrance(
            delay: const Duration(milliseconds: 40),
            child: Center(
              child: Text(
                'Add a photo so people recognize you',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          const SizedBox(height: AppSpace.xxxl),

          const _SectionLabel('Your identity'),
          Entrance(
            delay: const Duration(milliseconds: 60),
            child: _editable(_nameController, 'Full name'),
          ),
          const SizedBox(height: AppSpace.md),
          Entrance(
            delay: const Duration(milliseconds: 90),
            child: _editable(_nicknameController, 'Nickname'),
          ),
          const SizedBox(height: AppSpace.md),
          Entrance(
            delay: const Duration(milliseconds: 120),
            child: _editable(_bioController, 'Bio', maxLines: 2),
          ),

          const SizedBox(height: AppSpace.xxl),
          const _SectionLabel('Your college'),
          Entrance(
            delay: const Duration(milliseconds: 150),
            child: _dropdown('College', _college, kCollegeOptions, (v) => setState(() => _college = v)),
          ),
          const SizedBox(height: AppSpace.md),
          Entrance(
            delay: const Duration(milliseconds: 180),
            child: _dropdown('Year', _year, _years, (v) => setState(() => _year = v)),
          ),
          const SizedBox(height: AppSpace.md),
          Entrance(
            delay: const Duration(milliseconds: 210),
            child: _dropdown('Branch', _branch, _branches, (v) => setState(() => _branch = v)),
          ),

          const SizedBox(height: AppSpace.xxxl),
          Entrance(
            delay: const Duration(milliseconds: 250),
            child: SizedBox(
              height: 54,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  child: _loading
                      ? const SizedBox(
                          key: ValueKey('loading'),
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Continue', key: ValueKey('label')),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _editable(TextEditingController c, String label, {int maxLines = 1}) {
    return TextField(
      controller: c,
      maxLines: maxLines,
      decoration: InputDecoration(labelText: label),
    );
  }

  Widget _dropdown(
    String label,
    String? value,
    List<String> items,
    ValueChanged<String?> onChanged,
  ) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
      onChanged: onChanged,
      decoration: InputDecoration(labelText: label),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: AppColors.textMuted,
        ),
      ),
    );
  }
}
