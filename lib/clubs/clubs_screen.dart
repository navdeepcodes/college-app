import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'club_profile_screen.dart';
import 'create_club_screen.dart';
import '../utils/dedupe_stream_rows.dart';
import '../core/app_colors.dart';
import '../core/motion.dart';
import '../core/spacing.dart';
import '../core/widgets/empty_state.dart';
import '../core/widgets/entrance.dart';
import '../core/widgets/pressable.dart';
import '../core/widgets/skeleton.dart';

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
      appBar: AppBar(
        title: const Text('Clubs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded),
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
                const SizedBox(height: AppSpace.sm),
                _SegmentedControl(
                  selectedIndex: _selectedTab,
                  onChanged: (i) => setState(() => _selectedTab = i),
                ),
                const SizedBox(height: AppSpace.lg),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: AppMotion.fast,
                    child: _selectedTab == 0
                        ? _YourClubs(key: const ValueKey('your'), uid: uid)
                        : _ExploreClubs(key: const ValueKey('explore'), isAdmin: _isAdmin),
                  ),
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
      margin: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          _SegmentButton(
            label: 'Your clubs',
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
          duration: AppMotion.fast,
          curve: AppMotion.standard,
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected ? AppColors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13.5,
              color: selected ? Colors.white : AppColors.textSecondary,
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
  const _YourClubs({super.key, required this.uid});

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
          return const EmptyState(
            icon: Icons.error_outline_rounded,
            title: "Couldn't load your clubs",
            isError: true,
          );
        }

        if (snap.connectionState == ConnectionState.waiting) {
          return const _ClubGridSkeleton();
        }

        if (!snap.hasData || snap.data!.isEmpty) {
          return const EmptyState(
            icon: Icons.groups_outlined,
            title: 'No clubs yet',
            message: 'Join a club from Explore to see it here.',
          );
        }

        final clubIds = dedupeStreamRowsById(snap.data!)
            .map((e) => e['club_id'] as String)
            .toList();

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
  const _ExploreClubs({super.key, required this.isAdmin});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('clubs')
          .stream(primaryKey: ['id'])
          .limit(200),
      builder: (context, snap) {
        if (snap.hasError) {
          return const EmptyState(
            icon: Icons.error_outline_rounded,
            title: "Couldn't load clubs",
            isError: true,
          );
        }

        if (snap.connectionState == ConnectionState.waiting) {
          return const _ClubGridSkeleton();
        }

        if (!snap.hasData || snap.data!.isEmpty) {
          return const EmptyState(
            icon: Icons.explore_outlined,
            title: 'No clubs available yet',
            message: 'Be the first to start one.',
          );
        }

        return _ClubGrid(
          clubIds: dedupeStreamRowsById(snap.data!)
              .map((e) => e['id'] as String)
              .toList(),
          isAdmin: isAdmin,
        );
      },
    );
  }
}

class _ClubGridSkeleton extends StatelessWidget {
  const _ClubGridSkeleton();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(AppSpace.lg),
      itemCount: 4,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 0.72,
      ),
      itemBuilder: (_, __) => const Skeleton(
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.xl)),
      ),
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
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, 120),
      itemCount: clubIds.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 0.72,
      ),
      itemBuilder: (_, i) {
        return Entrance(
          key: ValueKey(clubIds[i]),
          duration: const Duration(milliseconds: 260),
          child: _ClubCard(clubId: clubIds[i], isAdmin: isAdmin),
        );
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
        if (snap.connectionState == ConnectionState.waiting || !snap.hasData || snap.data!.isEmpty) {
          return const Skeleton(borderRadius: BorderRadius.all(Radius.circular(AppRadius.xl)));
        }

        final data = snap.data!.first;
        final photoUrl =
            data['photo_url'] ?? data['image_url'] ?? data['logo_url'];

        return Pressable(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ClubProfileScreen(clubId: clubId),
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.xl),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.xl),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: photoUrl != null
                        ? Image.network(photoUrl, fit: BoxFit.cover, cacheWidth: 320)
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
                            color: AppColors.textSecondary,
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
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: AppColors.accentGradientSoft,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(Icons.groups_rounded, size: 44, color: Colors.white),
      ),
    );
  }
}
