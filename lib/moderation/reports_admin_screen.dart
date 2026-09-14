import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/dedupe_stream_rows.dart';

/// Admin-only visibility into filed reports (hardening pass task I).
/// Access itself isn't gated client-side -- reports_select's RLS policy
/// (reporter_uid = auth.uid() or is_platform_admin()) is what actually
/// stops a non-admin from seeing anyone else's reports; a non-admin who
/// somehow reaches this screen just sees an empty list, same as any other
/// admin-only screen in this app (see admin_club_requests_screen.dart).
class ReportsAdminScreen extends StatelessWidget {
  const ReportsAdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text('Reports'),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: Supabase.instance.client
            .from('reports')
            .stream(primaryKey: ['id'])
            .order('created_at', ascending: false)
            .limit(200),
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(
              child: Text('Failed to load reports',
                  style: TextStyle(color: Colors.white54)),
            );
          }
          if (!snap.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.deepPurple),
            );
          }

          final reports = dedupeStreamRowsById(snap.data!)
              .where((r) => r['status'] == 'open')
              .toList();

          if (reports.isEmpty) {
            return const Center(
              child: Text('No open reports',
                  style: TextStyle(color: Colors.white54)),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: reports.length,
            itemBuilder: (context, i) => _ReportCard(data: reports[i]),
          );
        },
      ),
    );
  }
}

class _ReportCard extends StatefulWidget {
  final Map<String, dynamic> data;
  const _ReportCard({required this.data});

  @override
  State<_ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends State<_ReportCard> {
  bool _busy = false;

  Future<void> _setStatus(String status) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Supabase.instance.client
          .from('reports')
          .update({'status': status})
          .eq('id', widget.data['id']);
    } catch (e) {
      debugPrint('Report status update failed: $e');
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not update. Try again.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    return Card(
      color: const Color(0xFF1E1E22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${d['target_type']} · ${d['reason']}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              'target: ${d['target_id']}',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
            if (d['details'] != null && (d['details'] as String).isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                d['details'],
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                    ),
                    onPressed: _busy ? null : () => _setStatus('dismissed'),
                    child: const Text('Dismiss'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                    ),
                    onPressed: _busy ? null : () => _setStatus('reviewed'),
                    child: const Text('Mark reviewed'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
