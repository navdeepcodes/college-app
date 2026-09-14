import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'club_join_requests_screen.dart';
import 'club_chat_screen.dart';
import '../core/app_colors.dart';
import '../core/spacing.dart';
import '../core/widgets/entrance.dart';
import '../core/widgets/pressable.dart';

class ClubAdminDashboardScreen extends StatelessWidget {
  final String clubId;
  final String clubName;

  const ClubAdminDashboardScreen({
    super.key,
    required this.clubId,
    required this.clubName,
  });

  @override
  Widget build(BuildContext context) {
    final uid = Supabase.instance.client.auth.currentUser?.id;

    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('Please login again')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Admin dashboard')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: Supabase.instance.client
            .from('club_members')
            .stream(primaryKey: ['id'])
            .eq('club_id', clubId)
            .eq('user_id', uid)
            .limit(1),
        builder: (context, snap) {
          if (!snap.hasData || snap.data!.isEmpty) {
            return const Center(
              child: Text('Access denied', style: TextStyle(color: AppColors.danger)),
            );
          }

          final member = snap.data!.first;
          final role = member['role'];

          if (role != 'admin') {
            return const Center(
              child: Text('Admins only', style: TextStyle(color: AppColors.danger)),
            );
          }

          final cards = [
            _DashboardCard(
              icon: Icons.person_add_alt_1_rounded,
              title: 'Join requests',
              subtitle: 'Approve or reject students',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ClubJoinRequestsScreen(clubId: clubId),
                  ),
                );
              },
            ),
            _DashboardCard(
              icon: Icons.group_outlined,
              title: 'Members',
              subtitle: 'View club members',
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Members screen coming soon')),
                );
              },
            ),
            _DashboardCard(
              icon: Icons.event_available_outlined,
              title: 'Events',
              subtitle: 'Create and manage events',
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Event creation coming soon')),
                );
              },
            ),
            _DashboardCard(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'Club chat',
              subtitle: 'Open admin chat',
              filled: true,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ClubChatScreen(clubId: clubId, clubName: clubName),
                  ),
                );
              },
            ),
          ];

          return ListView(
            padding: const EdgeInsets.all(AppSpace.xl),
            children: [
              Entrance(child: _Header(clubName: clubName)),
              const SizedBox(height: AppSpace.xxl),
              for (var i = 0; i < cards.length; i++)
                Entrance(
                  delay: Duration(milliseconds: 40 * i),
                  child: cards[i],
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String clubName;

  const _Header({required this.clubName});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Club admin', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(clubName, style: const TextStyle(color: AppColors.textMuted)),
      ],
    );
  }
}

class _DashboardCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool filled;

  const _DashboardCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpace.md),
        padding: const EdgeInsets.all(AppSpace.lg),
        decoration: BoxDecoration(
          color: filled ? AppColors.accent : AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: filled ? null : Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: filled ? Colors.white70 : AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Colors.white.withValues(alpha: filled ? 0.7 : 0.4)),
          ],
        ),
      ),
    );
  }
}
