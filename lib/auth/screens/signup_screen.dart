import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../app/auth_gate.dart';
import '../../auth/services/college_detector.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  String? _college;
  bool _loading = false;

  final List<String> colleges = const [
    'Ramaiah Institute of Technology',
    'PES University',
    'RV College of Engineering',
    'BMS College of Engineering',
    'Dayananda Sagar College of Engineering',
    'NMIT – Nitte Meenakshi Institute of Technology',
    'Christ University',
  ];

  bool _isCollegeEmail(String email) {
    final e = email.toLowerCase();
    return e.endsWith('.edu') ||
        e.endsWith('.ac.in') ||
        e.contains('nmit') ||
        e.contains('rvce') ||
        e.contains('bms');
  }

  Future<void> _signupWithGoogle() async {
    if (_college == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select your college')),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return;

      final googleAuth = await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
        accessToken: googleAuth.accessToken,
      );

      final result =
      await FirebaseAuth.instance.signInWithCredential(credential);

      final user = result.user!;
      final email = user.email ?? '';

      // 🚫 HARD BLOCK NON-COLLEGE EMAILS
      if (!_isCollegeEmail(email)) {
        await FirebaseAuth.instance.signOut();
        await GoogleSignIn().signOut();

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please use your official college email'),
          ),
        );
        return;
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(
        {
          'uid': user.uid,
          'email': email,
          'college': _college,
          // Must match the rules' users.create check (collegeIdForEmail ==
          // collegeIdFromEmail): a display-name fallback slug would be denied
          // for non-sanctioned domains, so derive from the email only; the
          // sanctioned domains resolve to their canonical slug, anything else
          // to 'unknown' (the same value users.create demands).
          'collegeId': collegeIdForEmail(email),
          'anonId': anonDisplayId(),
          'profileCompleted': false,
          'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
            (_) => false,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Signup failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 70),
            const Text(
              'Create your college account',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 32),
            DropdownButtonFormField<String>(
              value: _college,
              isExpanded: true,
              dropdownColor: Colors.grey.shade900,
              items: colleges
                  .map(
                    (c) => DropdownMenuItem(
                  value: c,
                  child: Text(
                    c,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              )
                  .toList(),
              onChanged: (v) => setState(() => _college = v),
              decoration: InputDecoration(
                labelText: 'Select your college',
                filled: true,
                fillColor: Colors.grey.shade900,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 36),
            ElevatedButton(
              onPressed: _loading ? null : _signupWithGoogle,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              child: _loading
                  ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : const Text(
                'Continue with Google',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}