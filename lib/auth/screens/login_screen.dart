import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../app/auth_gate.dart';
import '../../core/app_colors.dart';
import '../../core/spacing.dart';
import '../../core/widgets/entrance.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;

  bool _isCollegeEmail(String email) {
    final e = email.toLowerCase();
    return e.endsWith('.edu') ||
        e.endsWith('.ac.in') ||
        e.contains('nmit') ||
        e.contains('rvce') ||
        e.contains('bms');
  }

  Future<void> _loginWithEmail() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your email and password')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth
          .signInWithPassword(email: email, password: password);

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (_) => false,
      );
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Google Sign-In: does the same native sign-in as before (real Google
  // servers, unchanged), then exchanges the resulting ID token with
  // Supabase Auth via signInWithIdToken. This is code-correct, but the
  // Google provider's Client ID must be registered in the Supabase
  // dashboard (Authentication -> Providers -> Google) before it will
  // actually succeed — a real, unavoidable manual step (see
  // docs/supabase-auth-migration.md). The catch below surfaces that
  // specific failure clearly rather than pretending it worked.
  Future<void> _loginWithGoogle() async {
    setState(() => _loading = true);

    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return;

      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      if (idToken == null) {
        throw Exception('Google did not return an ID token');
      }

      await Supabase.instance.client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: googleAuth.accessToken,
      );

      final email = Supabase.instance.client.auth.currentUser?.email ?? '';

      if (!_isCollegeEmail(email)) {
        await Supabase.instance.client.auth.signOut();
        await GoogleSignIn().signOut();

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Only college email accounts are allowed'),
          ),
        );
        return;
      }

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (_) => false,
      );
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Google sign-in is not configured yet on the backend '
              '(${e.message}). Use email/password for now.',
            ),
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
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxxl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Entrance(
                child: Text('Welcome back', style: Theme.of(context).textTheme.headlineSmall),
              ),
              const SizedBox(height: AppSpace.sm),
              const Entrance(
                delay: Duration(milliseconds: 60),
                child: Text(
                  'Log in with your college email',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                ),
              ),
              const SizedBox(height: AppSpace.xxxl),
              Entrance(
                delay: const Duration(milliseconds: 100),
                child: TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'College email',
                    prefixIcon: Icon(Icons.mail_outline_rounded),
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              Entrance(
                delay: const Duration(milliseconds: 140),
                child: TextField(
                  controller: _passwordController,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _loading ? null : _loginWithEmail(),
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock_outline_rounded),
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.xxl),
              Entrance(
                delay: const Duration(milliseconds: 180),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _loginWithEmail,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 150),
                      child: _loading
                          ? const SizedBox(
                              key: ValueKey('loading'),
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Log in', key: ValueKey('label')),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              Entrance(
                delay: const Duration(milliseconds: 220),
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : _loginWithGoogle,
                  icon: const Icon(Icons.g_mobiledata_rounded, size: 24),
                  label: const Text('Continue with Google'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
