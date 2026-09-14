import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/spacing.dart';
import '../../core/widgets/entrance.dart';
import 'login_screen.dart';
import 'signup_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // A single static ambient glow behind the wordmark — the one
          // deliberate atmospheric touch on this screen, not a looping
          // animation competing for attention on the very first frame a
          // new user sees.
          Positioned(
            top: -140,
            left: -80,
            right: -80,
            child: Container(
              height: 420,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.accent.withValues(alpha: 0.35),
                    AppColors.accent.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxxl),
              child: Column(
                children: [
                  const Spacer(flex: 3),
                  Entrance(
                    offset: const Offset(0, 0.12),
                    child: Text(
                      'TrueKinn',
                      style: TextStyle(
                        fontSize: 44,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        fontFamily: Theme.of(context).textTheme.headlineLarge?.fontFamily,
                        letterSpacing: -1,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpace.md),
                  const Entrance(
                    delay: Duration(milliseconds: 90),
                    offset: Offset(0, 0.12),
                    child: Text(
                      'Posts, chats, and clubs — just for your college.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.4,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const Spacer(flex: 4),
                  Entrance(
                    delay: const Duration(milliseconds: 180),
                    offset: const Offset(0, 0.12),
                    child: Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const SignupScreen()),
                            ),
                            child: const Text('Get started'),
                          ),
                        ),
                        const SizedBox(height: AppSpace.md),
                        TextButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const LoginScreen()),
                          ),
                          child: const Text('Already have an account? Log in'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpace.md),
                  const Entrance(
                    delay: Duration(milliseconds: 240),
                    child: Text(
                      'Verified with your college email',
                      style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                  ),
                  const SizedBox(height: AppSpace.xxl),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
