import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../auth/services/college_detector.dart';

/// College-scoped events list — the read side of create_event_screen.dart's
/// write. Before this screen existed, an event could be created but never
/// viewed again by anyone, including its creator (confirmed via exhaustive
/// grep: create_event_screen.dart was the only file in lib/ that ever
/// touched the `events` collection). Mirrors feed_screen.dart's own-college
/// resolution + query pattern exactly — same data model, same rules
/// (firestore.rules events block, unchanged), no new fields, no new
/// collection.
class EventsScreen extends StatelessWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Events')),
      body: FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
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

          final collegeId = userSnap.hasData
              ? canonicalCollegeId(userSnap.data!.data() as Map<String, dynamic>?)
              : '';
          if (collegeId.isEmpty) {
            return const Center(
              child: Text(
                'Complete your profile to see campus events',
                style: TextStyle(color: Colors.white70),
              ),
            );
          }

          return StreamBuilder<QuerySnapshot>(
            // Same college-scoped shape as the posts feed query
            // (firestore.indexes.json has a matching composite index:
            // collegeId ASC, startDate ASC, __name__ ASC). isActive is
            // filtered client-side rather than added to the query, the
            // same choice moments_screen.dart makes for its own
            // client-only expiry filter — avoids a second equality clause
            // (and therefore a wider composite index) for a field nothing
            // currently ever sets to false.
            stream: FirebaseFirestore.instance
                .collection('events')
                .where('collegeId', isEqualTo: collegeId)
                .orderBy('startDate')
                .limit(100)
                .snapshots(),
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

              final docs = snap.data!.docs.where((d) {
                final data = d.data() as Map<String, dynamic>;
                return data['isActive'] != false;
              }).toList();

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
                itemBuilder: (context, i) {
                  final data = docs[i].data() as Map<String, dynamic>;
                  return _EventCard(data: data);
                },
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
    if (ts is! Timestamp) return '';
    final d = ts.toDate();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final title = (data['title'] as String?)?.trim();
    if (title == null || title.isEmpty) {
      // Defensive: a doc missing its required title shouldn't crash the
      // list (the create rule requires it, but this stays safe against any
      // legacy/malformed doc the same way feed_screen.dart already guards
      // posts missing mediaPath/userId).
      return const SizedBox.shrink();
    }

    final description = (data['description'] as String?) ?? '';
    final mediaPaths = (data['mediaPaths'] as List?)?.cast<String>() ?? const [];
    final startDate = _fmt(data['startDate']);
    final endDate = _fmt(data['endDate']);
    final eventLink = data['eventLink'] as String?;

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
