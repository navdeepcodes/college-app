import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'club_members_screen.dart';
import 'club_events_screen.dart';

class ClubAdminDashboard extends StatefulWidget {
  final String clubId;
  final String clubName;

  const ClubAdminDashboard({
    super.key,
    required this.clubId,
    required this.clubName,
  });

  @override
  State<ClubAdminDashboard> createState() => _ClubAdminDashboardState();
}

class _ClubAdminDashboardState extends State<ClubAdminDashboard> {
  int _selectedTab = 0;

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
        elevation: 0,
        backgroundColor: Colors.black,
        title: Text(
          widget.clubName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),

          // ================= SEGMENTED CONTROL =================
          _AdminSegmentedControl(
            selectedIndex: _selectedTab,
            onChanged: (i) => setState(() => _selectedTab = i),
          ),

          const SizedBox(height: 14),

          // ================= CONTENT =================
          Expanded(
            child: _selectedTab == 0
                ? ClubMembersScreen(clubId: widget.clubId)
                : ClubEventsScreen(
              clubId: widget.clubId,
              clubName: widget.clubName,
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================
// SEGMENTED CONTROL (ADMIN)
// =====================================================

class _AdminSegmentedControl extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const _AdminSegmentedControl({
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          _SegmentButton(
            label: 'Members',
            selected: selectedIndex == 0,
            onTap: () => onChanged(0),
          ),
          _SegmentButton(
            label: 'Events',
            selected: selectedIndex == 1,
            onTap: () => onChanged(1),
          ),
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? Colors.deepPurple : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }
}