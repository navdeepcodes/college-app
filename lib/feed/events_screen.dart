import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/services/college_detector.dart';

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
            return const Center(
              child: Text(
                'Failed to load your profile',
                style: TextStyle(color: Colors.white70),
              ),
            );
          }

          final collegeId = (userSnap.data?.isNotEmpty ?? false)
              ? canonicalCollegeId(userSnap.data!.first)
              : '';
          if (collegeId.isEmpty) {
            return const Center(
              child: Text(
                'Complete your profile to see campus events',
                style: TextStyle(color: Colors.white70),
              ),
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
                return const Center(
                  child: Text(
                    'Failed to load events',
                    style: TextStyle(color: Colors.white70),
                  ),
                );
              }

              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs =
                  snap.data!.where((d) => d['is_active'] != false).toList();

              if (docs.isEmpty) {
                return const Center(
                  child: Text(
                    'No upcoming events',
                    style: TextStyle(color: Colors.white70),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                itemBuilder: (context, i) => _EventCard(data: docs[i]),
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
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
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

    return Card(
      color: Colors.white10,
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: Colors.white,
              ),
            ),
            if (startDate.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                endDate.isNotEmpty && endDate != startDate
                    ? '$startDate – $endDate'
                    : startDate,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
            if (description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                description,
                style: const TextStyle(color: Colors.white70),
              ),
            ],
            if (mediaPaths.isNotEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 90,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: mediaPaths.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      mediaPaths[i],
                      width: 90,
                      height: 90,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 90,
                        height: 90,
                        color: Colors.white10,
                        child: const Icon(Icons.broken_image_outlined,
                            color: Colors.white38),
                      ),
                    ),
                  ),
                ),
              ),
            ],
            if (eventLink != null && eventLink.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                eventLink,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
