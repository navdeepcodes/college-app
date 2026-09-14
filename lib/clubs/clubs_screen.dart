import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'club_profile_screen.dart';
import 'create_club_screen.dart';

class ClubsScreen extends StatefulWidget {
  const ClubsScreen({super.key});

  @override
  State<ClubsScreen> createState() => _ClubsScreenState();
}

class _ClubsScreenState extends State<ClubsScreen> {
  int _selectedTab = 0;

  static const adminEmails = [
    '1nt24ae067.navdeep@nmit.ac.in',
  ];

  bool get _isAdmin {
    final email = Supabase.instance.client.auth.currentUser?.email;
    return email != null && adminEmails.contains(email);
  }

  @override
  Widget build(BuildContext context) {
    final uid = Supabase.instance.client.auth.currentUser?.id;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text('Clubs', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CreateClubScreen()),
              );
            },
          ),
        ],
      ),
      body: uid == null
          ? const Center(child: Text('Please login again'))
          : Column(
        children: [
          const SizedBox(height: 12),
          _SegmentedControl(
            selectedIndex: _selectedTab,
            onChanged: (i) => setState(() => _selectedTab = i),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _selectedTab == 0
                ? _YourClubs(uid: uid)
                : _ExploreClubs(isAdmin: _isAdmin),
          ),
        ],
      ),
    );
  }
}

// =====================================================
// SEGMENTED CONTROL
// =====================================================

class _SegmentedControl extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const _SegmentedControl({
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(32),
      ),
      child: Row(
        children: [
          _SegmentButton(
            label: 'Your Clubs',
            selected: selectedIndex == 0,
            onTap: () => onChanged(0),
          ),
          _SegmentButton(
            label: 'Explore',
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
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? Colors.deepPurple : Colors.transparent,
            borderRadius: BorderRadius.circular(28),
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

// =====================================================
// YOUR CLUBS
// =====================================================

class _YourClubs extends StatelessWidget {
  final String uid;
  const _YourClubs({required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('club_members')
          .stream(primaryKey: ['id'])
          .eq('user_id', uid)
          .limit(200),
      builder: (context, snap) {
        if (snap.hasError) {
          return const Center(child: Text('Failed to load your clubs'));
        }

        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snap.hasData || snap.data!.isEmpty) {
          return const Center(
            child: Text(
              'You are not part of any clubs yet',
              style: TextStyle(color: Colors.white54),
            ),
          );
        }

        final clubIds =
            snap.data!.map((e) => e['club_id'] as String).toList();

        return _ClubGrid(clubIds: clubIds, isAdmin: false);
      },
    );
  }
}

// =====================================================
// EXPLORE CLUBS
// =====================================================

class _ExploreClubs extends StatelessWidget {
  final bool isAdmin;
  const _ExploreClubs({required this.isAdmin});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('clubs')
          .stream(primaryKey: ['id'])
          .limit(200),
      builder: (context, snap) {
        if (snap.hasError) {
          return const Center(child: Text('Failed to load clubs'));
        }

        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snap.hasData || snap.data!.isEmpty) {
          return const Center(
            child: Text(
              'No clubs available yet',
              style: TextStyle(color: Colors.white54),
            ),
          );
        }

        return _ClubGrid(
          clubIds: snap.data!.map((e) => e['id'] as String).toList(),
          isAdmin: isAdmin,
        );
      },
    );
  }
}

// =====================================================
// CLUB GRID
// =====================================================

class _ClubGrid extends StatelessWidget {
  final List<String> clubIds;
  final bool isAdmin;

  const _ClubGrid({
    required this.clubIds,
    required this.isAdmin,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: clubIds.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 0.72,
      ),
      itemBuilder: (_, i) {
        return _ClubCard(clubId: clubIds[i], isAdmin: isAdmin);
      },
    );
  }
}

// =====================================================
// CLUB CARD
// =====================================================

class _ClubCard extends StatelessWidget {
  final String clubId;
  final bool isAdmin;

  const _ClubCard({
    required this.clubId,
    required this.isAdmin,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('clubs')
          .stream(primaryKey: ['id'])
          .eq('id', clubId)
          .limit(1),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _SkeletonCard();
        }

        if (!snap.hasData || snap.data!.isEmpty) {
          return _SkeletonCard();
        }

        final data = snap.data!.first;
        final photoUrl =
            data['photo_url'] ?? data['image_url'] ?? data['logo_url'];

        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ClubProfileScreen(clubId: clubId),
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: 18,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: photoUrl != null
                        ? Image.network(photoUrl, fit: BoxFit.cover)
                        : _fallback(),
                  ),
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.black.withValues(alpha: 0.1),
                            Colors.black.withValues(alpha: 0.85),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    bottom: 12,
                    right: 12,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data['name'] ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${data['members_count'] ?? 1} members',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _fallback() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.deepPurple.shade700,
            Colors.deepPurple.shade400,
          ],
        ),
      ),
      child: const Center(
        child: Icon(Icons.groups, size: 44, color: Colors.white),
      ),
    );
  }
}

// =====================================================
// SKELETON PLACEHOLDER
// =====================================================

class _SkeletonCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(26),
      ),
    );
  }
}
