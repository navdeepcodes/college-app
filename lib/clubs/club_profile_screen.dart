import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'club_chat_screen.dart';
import 'club_admin_dashboard_screen.dart';

class ClubProfileScreen extends StatelessWidget {
  final String clubId;

  const ClubProfileScreen({
    super.key,
    required this.clubId,
  });

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

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
        title: const Text('Club'),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('clubs')
            .doc(clubId)
            .snapshots(),
        builder: (context, clubSnap) {
          if (!clubSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!clubSnap.data!.exists) {
            return const Center(child: Text('Club not found'));
          }

          final club = clubSnap.data!.data() as Map<String, dynamic>;

          final clubName = club['name'] ?? 'Club';
          final clubDesc = club['description'] ?? '';
          final membersCount = club['membersCount'] ?? 1;
          final photoUrl = club['photoUrl'];

          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 36),
            children: [
              _HeroHeader(
                clubName: clubName,
                clubDesc: clubDesc,
                membersCount: membersCount,
                photoUrl: photoUrl,
              ),
              const SizedBox(height: 30),
              _RoleActions(
                clubId: clubId,
                clubName: clubName,
                uid: uid,
              ),
            ],
          );
        },
      ),
    );
  }
}

// =====================================================
// HERO HEADER
// =====================================================

class _HeroHeader extends StatelessWidget {
  final String clubName;
  final String clubDesc;
  final int membersCount;
  final String? photoUrl;

  const _HeroHeader({
    required this.clubName,
    required this.clubDesc,
    required this.membersCount,
    required this.photoUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFF6A3DE8), Color(0xFF3B1E91)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 46,
            backgroundColor: Colors.black,
            backgroundImage:
            photoUrl != null ? NetworkImage(photoUrl!) : null,
            child: photoUrl == null
                ? const Icon(Icons.groups, size: 42, color: Colors.white)
                : null,
          ),
          const SizedBox(height: 14),
          Text(
            clubName,
            style: const TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            clubDesc,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 14),
          Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              '$membersCount members',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================
// ROLE ACTIONS (THIS IS THE FIX)
// =====================================================

class _RoleActions extends StatelessWidget {
  final String clubId;
  final String clubName;
  final String uid;

  const _RoleActions({
    required this.clubId,
    required this.clubName,
    required this.uid,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('club_members')
          .doc('${clubId}_$uid')
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || !snap.data!.exists) {
          return _PrimaryButton(
            icon: Icons.person_add_alt_1,
            text: 'Request to Join Club',
            onTap: () async {
              await FirebaseFirestore.instance
                  .collection('club_join_requests')
                  .add({
                'clubId': clubId,
                'userId': uid,
                'status': 'pending',
                'createdAt': FieldValue.serverTimestamp(),
              });

              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Join request sent')),
              );
            },
          );
        }

        final role =
        (snap.data!.data() as Map<String, dynamic>)['role'];

        // ================= ADMIN VIEW =================
        if (role == 'admin') {
          return Column(
            children: [
              _AdminDashboardCard(
                clubId: clubId,
                clubName: clubName,
              ),
              const SizedBox(height: 18),
              _PrimaryButton(
                icon: Icons.chat_bubble_outline,
                text: 'Open Club Chat',
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
        }

        // ================= MEMBER VIEW =================
        return _PrimaryButton(
          icon: Icons.chat_bubble_outline,
          text: 'Open Club Chat',
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
        );
      },
    );
  }
}

// =====================================================
// ADMIN DASHBOARD CARD (POWER FEEL)
// =====================================================

class _AdminDashboardCard extends StatelessWidget {
  final String clubId;
  final String clubName;

  const _AdminDashboardCard({
    required this.clubId,
    required this.clubName,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ClubAdminDashboardScreen(
              clubId: clubId,
              clubName: clubName,
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            colors: [
              Colors.purple.withValues(alpha: 0.35),
              Colors.deepPurple.withValues(alpha: 0.2),
            ],
          ),
          border: Border.all(color: Colors.purpleAccent),
        ),
        child: const Row(
          children: [
            Icon(Icons.dashboard, color: Colors.purpleAccent, size: 26),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Admin Dashboard',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Members • Requests • Events',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}

// =====================================================
// PRIMARY BUTTON
// =====================================================

class _PrimaryButton extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback onTap;

  const _PrimaryButton({
    required this.icon,
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 54,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.deepPurple,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}