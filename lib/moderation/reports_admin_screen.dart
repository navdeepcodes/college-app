import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/dedupe_stream_rows.dart';
import '../core/app_colors.dart';
import '../core/haptics.dart';
import '../core/widgets/empty_state.dart';
import '../core/widgets/entrance.dart';
import '../core/widgets/relative_time.dart';
import '../core/widgets/request_card.dart';

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
      appBar: AppBar(title: const Text('Reports')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: Supabase.instance.client
            .from('reports')
            .stream(primaryKey: ['id'])
            .order('created_at', ascending: false)
            .limit(200),
        builder: (context, snap) {
          if (snap.hasError) {
            return const EmptyState(
              icon: Icons.error_outline_rounded,
              title: "Couldn't load reports",
              isError: true,
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final reports = dedupeStreamRowsById(snap.data!)
              .where((r) => r['status'] == 'open')
              .toList();

          if (reports.isEmpty) {
            return const EmptyState(
              icon: Icons.shield_outlined,
              title: 'No open reports',
              message: 'Nothing needs your attention right now.',
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: reports.length,
            itemBuilder: (context, i) => Entrance(
              key: ValueKey(reports[i]['id']),
              delay: Duration(milliseconds: 30 * i),
              child: _ReportCard(data: reports[i]),
            ),
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
      AppHaptics.confirm();
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
    final createdAtRaw = d['created_at'] as String?;
    final createdAt = createdAtRaw != null ? DateTime.tryParse(createdAtRaw) : null;

    return RequestCard(
      title: '${d['target_type']} · ${d['reason']}',
      subtitle: createdAt != null ? relativeTime(createdAt) : null,
      busy: _busy,
      extras: [
        Text('Target: ${d['target_id']}', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
        if (d['details'] != null && (d['details'] as String).isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(d['details'], style: Theme.of(context).textTheme.bodyMedium),
        ],
      ],
      secondaryLabel: 'Dismiss',
      onSecondary: () => _setStatus('dismissed'),
      primaryLabel: 'Mark reviewed',
      onPrimary: () => _setStatus('reviewed'),
    );
  }
}
