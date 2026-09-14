import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'club_join_requests_screen.dart';
import 'club_chat_screen.dart';

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
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text('Admin Dashboard'),
      ),
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
              child: Text(
                'Access denied',
                style: TextStyle(color: Colors.redAccent),
              ),
            );
          }

          final member = snap.data!.first;
          final role = member['role'];

          if (role != 'admin') {
            return const Center(
              child: Text(
                'Admins only',
                style: TextStyle(color: Colors.redAccent),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _Header(clubName: clubName),
              const SizedBox(height: 24),
              _DashboardCard(
                icon: Icons.person_add_alt_1,
                title: 'Join Requests',
                subtitle: 'Approve or reject students',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ClubJoinRequestsScreen(clubId: clubId),
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
                    const SnackBar(
                      content: Text('Members screen coming next'),
                    ),
                  );
                },
              ),
              _DashboardCard(
                icon: Icons.event_available_outlined,
                title: 'Events',
                subtitle: 'Create and manage events',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Event creation coming next'),
                    ),
                  );
                },
              ),
              _DashboardCard(
                icon: Icons.chat_bubble_outline,
                title: 'Club Chat',
                subtitle: 'Open admin chat',
                filled: true,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ClubChatScreen(
                        clubId: clubId,
                        clubName: clubName,
                      ),
                    ),
                  );
                },
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
        const Text(
          'Club Admin',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          clubName,
          style: const TextStyle(color: Colors.white54),
        ),
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: filled ? Colors.deepPurple : const Color(0xFF141414),
          borderRadius: BorderRadius.circular(20),
          border: filled ? null : Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 26),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white54,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}
