import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class EmailLoginScreen extends StatefulWidget {
  const EmailLoginScreen({super.key});

  @override
  State<EmailLoginScreen> createState() => _EmailLoginScreenState();
}

class _EmailLoginScreenState extends State<EmailLoginScreen> {
  final _emailController = TextEditingController();
  bool _loading = false;

  Future<void> _sendLink() async {
    final email = _emailController.text.trim();

    if (!email.endsWith('.ac.in')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Use your college email')),
      );
      return;
    }

    setState(() => _loading = true);

    final settings = ActionCodeSettings(
      url: 'https://collegeapp.page.link/login',
      handleCodeInApp: true,
      androidPackageName: 'com.navdeep.collegeapp',
      androidInstallApp: true,
      androidMinimumVersion: '21',
      iOSBundleId: 'com.navdeep.collegeapp',
    );

    await FirebaseAuth.instance.sendSignInLinkToEmail(
      email: email,
      actionCodeSettings: settings,
    );

    setState(() => _loading = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Login link sent to your email'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Login with College Email',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                hintText: 'usn@nmit.ac.in',
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loading ? null : _sendLink,
              child: _loading
                  ? const CircularProgressIndicator()
                  : const Text('Send Login Link'),
            ),
          ],
        ),
      ),
    );
  }
}