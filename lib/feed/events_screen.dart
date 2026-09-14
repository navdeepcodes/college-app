import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/services/college_detector.dart';
import '../core/app_colors.dart';
import '../core/spacing.dart';
import '../core/widgets/empty_state.dart';
import '../core/widgets/entrance.dart';

/// College-scoped events list — the read side of create_event_screen.dart's
/// write. Ported from the Firestore version (lib/feed/events_screen.dart,
/// Phase 25 of the Firebase hardening work) onto the events table built in
/// supabase/migrations/20260914000001_initial_schema.sql. Same query shape
/// (college-scoped, ordered by start date), same RLS-enforced isolation —
/// see docs/supabase-security-model.md.
class EventsScreen extends StatelessWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final supabase = Supabase.instance.client;
    final uid = supabase.auth.currentUser!.id;

    return Scaffold(
      appBar: AppBar(title: const Text('Events')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: supabase.from('profiles').select().eq('id', uid).limit(1),
        builder: (context, userSnap) {
          if (userSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (userSnap.hasError) {
            return const EmptyState(
              icon: Icons.error_outline_rounded,
              title: "Couldn't load your profile",
              isError: true,
            );
          }

          final collegeId = (userSnap.data?.isNotEmpty ?? false)
              ? canonicalCollegeId(userSnap.data!.first)
              : '';
          if (collegeId.isEmpty) {
            return const EmptyState(
              icon: Icons.badge_outlined,
              title: 'Finish your profile',
              message: 'Complete your profile to see campus events.',
            );
          }

          return StreamBuilder<List<Map<String, dynamic>>>(
            stream: supabase
                .from('events')
                .stream(primaryKey: ['id'])
                .eq('college_id', collegeId)
                .order('start_date'),
            builder: (context, snap) {
              if (snap.hasError) {
                return const EmptyState(
                  icon: Icons.error_outline_rounded,
                  title: "Couldn't load events",
                  isError: true,
                );
              }

              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs =
                  snap.data!.where((d) => d['is_active'] != false).toList();

              if (docs.isEmpty) {
                return const EmptyState(
                  icon: Icons.event_outlined,
                  title: 'No upcoming events',
                  message: 'Events your campus posts will show up here.',
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(AppSpace.lg),
                itemCount: docs.length,
                itemBuilder: (context, i) => Entrance(
                  key: ValueKey(docs[i]['id']),
                  delay: Duration(milliseconds: 30 * i),
                  child: _EventCard(data: docs[i]),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  final Map<String, dynamic> data;

  const _EventCard({required this.data});

  String _fmt(dynamic ts) {
    if (ts is! String) return '';
    final d = DateTime.tryParse(ts);
    if (d == null) return '';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final title = (data['title'] as String?)?.trim();
    if (title == null || title.isEmpty) {
      return const SizedBox.shrink();
    }

    final description = (data['description'] as String?) ?? '';
    final mediaPaths = (data['media_paths'] as List?)?.cast<String>() ?? const [];
    final startDate = _fmt(data['start_date']);
    final endDate = _fmt(data['end_date']);
    final eventLink = data['event_link'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.md),
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (startDate.isNotEmpty)
                Container(
                  width: 46,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    startDate,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.accentBright,
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                      height: 1.2,
                    ),
                  ),
                ),
              if (startDate.isNotEmpty) const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    if (startDate.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          endDate.isNotEmpty && endDate != startDate
                              ? '$startDate – $endDate'
                              : startDate,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            Text(description, style: Theme.of(context).textTheme.bodyMedium),
          ],
          if (mediaPaths.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            SizedBox(
              height: 90,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: mediaPaths.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    mediaPaths[i],
                    width: 90,
                    height: 90,
                    fit: BoxFit.cover,
                    cacheWidth: 180,
                    errorBuilder: (_, __, ___) => Container(
                      width: 90,
                      height: 90,
                      color: AppColors.surfaceSunken,
                      child: const Icon(Icons.broken_image_outlined, color: AppColors.textMuted),
                    ),
                  ),
                ),
              ),
            ),
          ],
          if (eventLink != null && eventLink.isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            Text(eventLink, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
          ],
        ],
      ),
    );
  }
}
