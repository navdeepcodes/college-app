import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../feed/feed_screen.dart';
import '../search/search_screen.dart';
import '../clubs/clubs_screen.dart';
import '../profile/profile_screen.dart';
import '../anon/anon_home_screen.dart';
import '../core/app_colors.dart';
import '../core/haptics.dart';
import '../core/motion.dart';
import '../core/widgets/avatar.dart';

class BottomNavShell extends StatefulWidget {
  const BottomNavShell({super.key});

  @override
  State<BottomNavShell> createState() => _BottomNavShellState();
}

class _BottomNavShellState extends State<BottomNavShell> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.accentBright),
        ),
      );
    }

    final uid = user.id;

    // IndexedStack instead of rebuilding `screens[_currentIndex]` from
    // scratch on every switch: each tab now keeps its scroll position,
    // its in-flight stream subscriptions, and its widget state across
    // switches, instead of re-fetching and resetting to the top every
    // single time — a real state/performance fix, not just visual.
    final screens = [
      const FeedScreen(),
      const SearchScreen(),
      const SizedBox(),
      const ClubsScreen(),
      ProfileScreen(userId: uid),
    ];

    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _currentIndex, children: screens),

      bottomNavigationBar: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.background.withValues(alpha: 0.78),
              border: const Border(
                top: BorderSide(color: AppColors.border, width: 0.75),
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: SafeArea(
              top: false,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _NavIcon(
                    icon: Icons.home_rounded,
                    selected: _currentIndex == 0,
                    onTap: () => _select(0),
                  ),
                  _NavIcon(
                    icon: Icons.search_rounded,
                    selected: _currentIndex == 1,
                    onTap: () => _select(1),
                  ),
                  _NavIcon(
                    icon: Icons.visibility_off_rounded,
                    selected: false,
                    onTap: _openAnon,
                  ),
                  _NavIcon(
                    icon: Icons.groups_rounded,
                    selected: _currentIndex == 3,
                    onTap: () => _select(3),
                  ),
                  _ProfileNavIcon(
                    uid: uid,
                    selected: _currentIndex == 4,
                    onTap: () => _select(4),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _select(int index) {
    if (index == _currentIndex) return;
    AppHaptics.select();
    setState(() => _currentIndex = index);
  }

  Future<void> _openAnon() async {
    AppHaptics.select();
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AnonHomeScreen()),
    );
  }
}

class _NavIcon extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _NavIcon({required this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 28,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.standard,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? AppColors.accent.withValues(alpha: 0.22) : Colors.transparent,
        ),
        child: Icon(
          icon,
          size: 22,
          color: selected ? AppColors.textPrimary : AppColors.textMuted,
        ),
      ),
    );
  }
}

class _ProfileNavIcon extends StatelessWidget {
  final String uid;
  final bool selected;
  final VoidCallback onTap;

  const _ProfileNavIcon({required this.uid, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('profiles')
          .stream(primaryKey: ['id'])
          .eq('id', uid)
          .limit(1),
      builder: (context, snap) {
        String? photoUrl;
        String name = '';

        if (snap.hasData && snap.data!.isNotEmpty) {
          photoUrl = snap.data!.first['photo_url'];
          name = snap.data!.first['name'] ?? '';
        }

        return InkResponse(
          onTap: onTap,
          radius: 28,
          child: AnimatedContainer(
            duration: AppMotion.fast,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? AppColors.accentBright : Colors.transparent,
                width: 1.6,
              ),
            ),
            child: AppAvatar(photoUrl: photoUrl, name: name, radius: 12),
          ),
        );
      },
    );
  }
}
