import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../auth/screens/welcome_screen.dart';
import '../auth/screens/profile_setup_page.dart';
import '../navigation/bottom_nav_shell.dart';
import '../auth/services/college_detector.dart';

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
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() => _failed = false);

    try {
      final ref =
      FirebaseFirestore.instance.collection('users').doc(widget.user.uid);

      final snap = await ref.get();

      if (!snap.exists) {
        // Bootstrap doc must satisfy the users.create rule: collegeId must
        // equal collegeIdFromEmail(email). Profile flows then refine the rest
        // (name/photo/college label). anonId is minted here ONCE so anon chat
        // works for every user, not just signup-screen users.
        await ref.set({
          'uid': widget.user.uid,
          'email': widget.user.email,
          'collegeId': collegeIdForEmail(widget.user.email),
          'anonId': anonDisplayId(),
          'profileCompleted': false,
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

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

      // A transient network/backend failure here is NOT the same as "this
      // user hasn't completed onboarding yet" — collapsing them used to
      // silently route an existing, fully-onboarded user back into
      // ProfileSetupPage on any blip (dropped connection, permission hiccup
      // on cold start). Show a retry screen instead so the distinction is
      // visible and recoverable.
      if (mounted) {
        setState(() => _failed = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return _BootstrapError(onRetry: _bootstrap);
    }

    if (_profileCompleted == null) {
      return const _Loading();
    }

    return _profileCompleted!
        ? const BottomNavShell()
        : const ProfileSetupPage();
  }
}

class _BootstrapError extends StatelessWidget {
  final VoidCallback onRetry;
  const _BootstrapError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, color: Colors.white54, size: 40),
              const SizedBox(height: 16),
              const Text(
                "Couldn't reach the server. Check your connection and try again.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
              TextButton(
                onPressed: () => FirebaseAuth.instance.signOut(),
                child: const Text(
                  'Sign out',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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