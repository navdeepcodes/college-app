import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/screens/welcome_screen.dart';
import '../auth/screens/profile_setup_page.dart';
import '../navigation/bottom_nav_shell.dart';
import '../auth/services/college_detector.dart';
import '../core/app_colors.dart';
import '../core/spacing.dart';

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
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      initialData: AuthState(
        AuthChangeEvent.initialSession,
        Supabase.instance.client.auth.currentSession,
      ),
      builder: (context, snap) {
        final session = snap.data?.session ?? Supabase.instance.client.auth.currentSession;

        // 1️⃣ No session → Welcome
        if (session == null) {
          return const WelcomeScreen();
        }

        final user = session.user;
        final email = user.email ?? '';

        // 2️⃣ College email guard (SAFE)
        if (!_isCollegeEmail(email)) {
          return _ForceSignOut();
        }

        // 3️⃣ Session exists → Bootstrap
        return _UserBootstrap(
          key: ValueKey(user.id),
          userId: user.id,
          email: email,
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
    await Supabase.instance.client.auth.signOut();
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
  final String userId;
  final String email;
  const _UserBootstrap({super.key, required this.userId, required this.email});

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
      final client = Supabase.instance.client;

      // A missing row reads back as an empty result, not an error — see
      // docs/supabase-schema.md for why this bug class (the one that broke
      // every new Firestore signup, Phase 20 of the Firebase hardening
      // work) cannot recur here: no special-casing needed, unlike
      // auth_gate.dart's old try/get/catch dance.
      final rows = await client
          .from('profiles')
          .select()
          .eq('id', widget.userId)
          .limit(1);

      if (rows.isEmpty) {
        // Bootstrap row must satisfy profiles_insert (id = auth.uid()) and
        // the enforce_college_id_on_insert trigger (collegeId must equal
        // collegeIdFromEmail(email)). anonId is minted here ONCE so anon
        // chat works for every user, not just signup-screen users — same
        // contract as the Firestore version.
        try {
          await client.from('profiles').insert({
            'id': widget.userId,
            'email': widget.email,
            'college_id': collegeIdForEmail(widget.email),
            'anon_id': anonDisplayId(),
            'profile_completed': false,
          });
        } on PostgrestException catch (e) {
          // Confirmed live on-device (not a theoretical worry): the auth
          // state stream can fire this bootstrap from more than one
          // still-mounted AuthGate at once right after a real sign-in
          // (e.g. the instance beneath a just-popped LoginScreen reacting
          // to the same event a fraction of a second before its own route
          // is torn down) — two concurrent inserts for the same id, one
          // wins, the other hits profiles_pkey. That's not a real
          // failure: the row exists either way, so treat exactly this
          // error as "someone else already created it" and fall through
          // to re-read it, rather than surfacing the retry screen for a
          // race that isn't actually broken.
          if (e.code != '23505') rethrow;
        }

        if (!mounted) return;
        final freshRows = await client
            .from('profiles')
            .select()
            .eq('id', widget.userId)
            .limit(1);
        setState(() {
          _profileCompleted =
              freshRows.isNotEmpty && freshRows.first['profile_completed'] == true;
        });
        return;
      }

      final data = rows.first;
      if (!mounted) return;

      setState(() {
        _profileCompleted = data['profile_completed'] == true;
      });
    } catch (e) {
      debugPrint('Auth bootstrap error: $e');

      // A transient network/backend failure here is NOT the same as "this
      // user hasn't completed onboarding yet" — collapsing them used to
      // silently route an existing, fully-onboarded user back into
      // ProfileSetupPage on any blip. Show a retry screen instead.
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
      backgroundColor: AppColors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xxxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, color: AppColors.textMuted, size: 40),
              const SizedBox(height: AppSpace.lg),
              Text(
                "Couldn't reach the server. Check your connection and try again.",
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpace.xl),
              ElevatedButton(
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
              const SizedBox(height: AppSpace.sm),
              TextButton(
                onPressed: () => Supabase.instance.client.auth.signOut(),
                child: const Text('Sign out'),
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
      backgroundColor: AppColors.background,
      body: Center(
        child: CircularProgressIndicator(color: AppColors.accentBright),
      ),
    );
  }
}
