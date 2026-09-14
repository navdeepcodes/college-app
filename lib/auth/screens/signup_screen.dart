import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../app/auth_gate.dart';
import '../../auth/services/college_detector.dart';
import '../../core/app_colors.dart';
import '../../core/spacing.dart';
import '../../core/widgets/entrance.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _college;
  bool _loading = false;

  bool _isCollegeEmail(String email) {
    final e = email.toLowerCase();
    return e.endsWith('.edu') ||
        e.endsWith('.ac.in') ||
        e.contains('nmit') ||
        e.contains('rvce') ||
        e.contains('bms');
  }

  Future<void> _bootstrapProfile(String userId, String email) async {
    // Same contract as auth_gate.dart's _UserBootstrap, plus the college
    // display-name fallback this screen collects for unsanctioned-domain
    // signups (collegeIdForEmail(email, fallbackCollege: ...) slugifies it
    // when the email domain itself isn't one of the four sanctioned ones).
    await Supabase.instance.client.from('profiles').insert({
      'id': userId,
      'email': email,
      'college_id': collegeIdForEmail(email, fallbackCollege: _college),
      'anon_id': anonDisplayId(),
      'profile_completed': false,
    });
  }

  Future<void> _signupWithEmail() async {
    if (_college == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select your college')),
      );
      return;
    }

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Enter a college email and a password (6+ chars)')),
      );
      return;
    }

    // Hard block non-college emails, same as the original Google-only flow
    // — now checked BEFORE creating the account instead of after.
    if (!_isCollegeEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please use your official college email')),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final response = await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
      );

      final session = response.session;
      final user = response.user;

      if (session == null || user == null) {
        // Email confirmation is required before a session exists. This is
        // the correct, expected outcome for a real signup (not an error) —
        // the profile row is bootstrapped on first real sign-in instead
        // (auth_gate.dart's _UserBootstrap), once a session actually
        // exists to write it under.
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Check your email to confirm your account, then log in.'),
          ),
        );
        return;
      }

      await _bootstrapProfile(user.id, email);

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (_) => false,
      );
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Signup failed: ${e.message}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Signup failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // See login_screen.dart's _loginWithGoogle for the same real-but-blocked
  // Google Sign-In note: needs the Client ID registered in the Supabase
  // dashboard before this succeeds.
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
      final idToken = googleAuth.idToken;
      if (idToken == null) {
        throw Exception('Google did not return an ID token');
      }

      await Supabase.instance.client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: googleAuth.accessToken,
      );

      final user = Supabase.instance.client.auth.currentUser!;
      final email = user.email ?? '';

      if (!_isCollegeEmail(email)) {
        await Supabase.instance.client.auth.signOut();
        await GoogleSignIn().signOut();

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please use your official college email')),
        );
        return;
      }

      // Bootstrap only if this is genuinely a new profile (a returning
      // Google user hitting "sign up" again should just proceed, not error
      // on a duplicate-key insert).
      final existing = await Supabase.instance.client
          .from('profiles')
          .select('id')
          .eq('id', user.id)
          .limit(1);
      if (existing.isEmpty) {
        await _bootstrapProfile(user.id, email);
      }

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Signup failed: $e')),
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
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.xxxl, AppSpace.lg, AppSpace.xxxl, AppSpace.xxxl,
          ),
          children: [
            Entrance(
              child: Text('Create your college account',
                  style: Theme.of(context).textTheme.headlineSmall),
            ),
            const SizedBox(height: AppSpace.sm),
            const Entrance(
              delay: Duration(milliseconds: 60),
              child: Text(
                'A few details, then you\'re in',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ),
            ),
            const SizedBox(height: AppSpace.xxxl),
            Entrance(
              delay: const Duration(milliseconds: 100),
              child: DropdownButtonFormField<String>(
                initialValue: _college,
                isExpanded: true,
                items: kCollegeOptions
                    .map((c) => DropdownMenuItem(
                          value: c,
                          child: Text(c, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _college = v),
                decoration: const InputDecoration(
                  labelText: 'Your college',
                  prefixIcon: Icon(Icons.school_outlined),
                ),
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            Entrance(
              delay: const Duration(milliseconds: 140),
              child: TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'College email',
                  prefixIcon: Icon(Icons.mail_outline_rounded),
                ),
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            Entrance(
              delay: const Duration(milliseconds: 180),
              child: TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  helperText: 'At least 6 characters',
                  prefixIcon: Icon(Icons.lock_outline_rounded),
                ),
              ),
            ),
            const SizedBox(height: AppSpace.xxl),
            Entrance(
              delay: const Duration(milliseconds: 220),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _signupWithEmail,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    child: _loading
                        ? const SizedBox(
                            key: ValueKey('loading'),
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Sign up', key: ValueKey('label')),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpace.md),
            Entrance(
              delay: const Duration(milliseconds: 260),
              child: OutlinedButton.icon(
                onPressed: _loading ? null : _signupWithGoogle,
                icon: const Icon(Icons.g_mobiledata_rounded, size: 24),
                label: const Text('Continue with Google'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
