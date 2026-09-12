import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../auth/screens/welcome_screen.dart';
import '../auth/screens/profile_setup_page.dart';
import '../navigation/bottom_nav_shell.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  bool _isCollegeEmail(String email) {
    final e = email.toLowerCase();
    return e.endsWith('.edu') ||
        e.endsWith('.ac.in') ||
        e.contains('nmit') ||
        e.contains('rvce') ||
        e.contains('bms');
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _Loading();
        }

        // 1️⃣ No user → Welcome
        if (!snap.hasData) {
          return const WelcomeScreen();
        }

        final user = snap.data!;
        final email = user.email ?? '';

        // 2️⃣ College email guard (SAFE)
        if (!_isCollegeEmail(email)) {
          return _ForceSignOut();
        }

        // 3️⃣ User exists → Bootstrap
        return _UserBootstrap(
          key: ValueKey(user.uid),
          user: user,
        );
      },
    );
  }
}

/* =========================================================
   FORCE SIGN OUT — RUNS ONCE, NEVER LOOPS
   ========================================================= */

class _ForceSignOut extends StatefulWidget {
  @override
  State<_ForceSignOut> createState() => _ForceSignOutState();
}

class _ForceSignOutState extends State<_ForceSignOut> {
  @override
  void initState() {
    super.initState();
    _signOut();
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return const WelcomeScreen();
  }
}

/* =========================================================
   USER BOOTSTRAP
   ========================================================= */

class _UserBootstrap extends StatefulWidget {
  final User user;
  const _UserBootstrap({super.key, required this.user});

  @override
  State<_UserBootstrap> createState() => _UserBootstrapState();
}

class _UserBootstrapState extends State<_UserBootstrap> {
  bool? _profileCompleted;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final ref =
      FirebaseFirestore.instance.collection('users').doc(widget.user.uid);

      final snap = await ref.get();

      if (!snap.exists) {
        await ref.set({
          'uid': widget.user.uid,
          'email': widget.user.email,
          'profileCompleted': false,
          'createdAt': FieldValue.serverTimestamp(),
        });

        if (!mounted) return;
        setState(() => _profileCompleted = false);
        return;
      }

      final data = snap.data();
      if (!mounted) return;

      setState(() {
        _profileCompleted = data?['profileCompleted'] == true;
      });
    } catch (e) {
      debugPrint('Auth bootstrap error: $e');

      if (mounted) {
        setState(() => _profileCompleted = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_profileCompleted == null) {
      return const _Loading();
    }

    return _profileCompleted!
        ? const BottomNavShell()
        : const ProfileSetupPage();
  }
}

/* ========================================================= */

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: CircularProgressIndicator(color: Colors.redAccent),
      ),
    );
  }
}