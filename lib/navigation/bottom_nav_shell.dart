import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../feed/feed_screen.dart';
import '../search/search_screen.dart';
import '../clubs/clubs_screen.dart';
import '../profile/profile_screen.dart';
import '../anon/anon_home_screen.dart';

class BottomNavShell extends StatefulWidget {
  const BottomNavShell({super.key});

  @override
  State<BottomNavShell> createState() => _BottomNavShellState();
}

class _BottomNavShellState extends State<BottomNavShell> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.deepPurple),
        ),
      );
    }

    final uid = user.uid;

    final screens = [
      const FeedScreen(),
      const SearchScreen(),
      const SizedBox(),
      const ClubsScreen(),
      ProfileScreen(userId: uid),
    ];

    return Scaffold(
      extendBody: true,
      body: screens[_currentIndex],

      bottomNavigationBar: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.75),
              border: const Border(
                top: BorderSide(color: Colors.white12, width: 0.5),
              ),
            ),
            child: BottomNavigationBar(
              currentIndex: _currentIndex,
              type: BottomNavigationBarType.fixed,
              backgroundColor: Colors.transparent,
              elevation: 0,
              selectedItemColor: Colors.white,
              unselectedItemColor: Colors.white54,
              showSelectedLabels: false,
              showUnselectedLabels: false,

              onTap: (index) async {
                if (index == 2) {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AnonHomeScreen(),
                    ),
                  );
                  return;
                }
                setState(() => _currentIndex = index);
              },

              items: [
                const BottomNavigationBarItem(
                  icon: Icon(Icons.home_rounded),
                  label: 'Home',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.search_rounded),
                  label: 'Search',
                ),
                BottomNavigationBarItem(
                  icon: _AnonNavIcon(
                    selected: _currentIndex == 2,
                  ),
                  label: 'Anon',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.groups_rounded),
                  label: 'Clubs',
                ),
                BottomNavigationBarItem(
                  icon: _ProfileNavIcon(uid: uid),
                  label: 'Profile',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnonNavIcon extends StatelessWidget {
  final bool selected;

  const _AnonNavIcon({required this.selected});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected
            ? Colors.deepPurple.withValues(alpha: 0.35)
            : Colors.transparent,
      ),
      child: const Icon(Icons.visibility_off_rounded, size: 22),
    );
  }
}

class _ProfileNavIcon extends StatelessWidget {
  final String uid;

  const _ProfileNavIcon({required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots(),
      builder: (context, snap) {
        String? photoUrl;

        if (snap.hasData && snap.data!.exists) {
          final data = snap.data!.data() as Map<String, dynamic>;
          photoUrl = data['photoUrl'];
        }

        return CircleAvatar(
          radius: 14,
          backgroundColor: Colors.white24,
          backgroundImage:
          photoUrl != null ? NetworkImage(photoUrl) : null,
          child: photoUrl == null
              ? const Icon(Icons.person, size: 16)
              : null,
        );
      },
    );
  }
}