import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/dedupe_stream_rows.dart';
import '../core/app_colors.dart';
import '../core/haptics.dart';
import '../core/spacing.dart';
import '../core/widgets/empty_state.dart';
import '../core/widgets/entrance.dart';
import '../core/widgets/request_card.dart';
import '../core/widgets/skeleton.dart';

class AdminClubRequestsScreen extends StatelessWidget {
  const AdminClubRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Club creation requests')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: Supabase.instance.client
            .from('club_requests')
            .stream(primaryKey: ['id'])
            .eq('status', 'pending'),
        builder: (context, snap) {
          if (snap.hasError) {
            return const EmptyState(
              icon: Icons.error_outline_rounded,
              title: "Couldn't load club requests",
              isError: true,
            );
          }

          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = dedupeStreamRowsById(snap.data ?? []);

          if (docs.isEmpty) {
            return const EmptyState(
              icon: Icons.inbox_outlined,
              title: 'No pending club requests',
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index];
              return Entrance(
                key: ValueKey(data['id']),
                delay: Duration(milliseconds: 30 * index),
                child: _ClubRequestCard(
                  requestId: data['id'] as String,
                  data: data,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ClubRequestCard extends StatefulWidget {
  final String requestId;
  final Map<String, dynamic> data;

  const _ClubRequestCard({required this.requestId, required this.data});

  @override
  State<_ClubRequestCard> createState() => _ClubRequestCardState();
}

class _ClubRequestCardState extends State<_ClubRequestCard> {
  bool _busy = false;

  // Atomic on the database side now (approve_club_request RPC, see
  // supabase/migrations/20260914000007_approve_club_request_rpc.sql) --
  // no client-driven multi-statement transaction needed or possible over
  // PostgREST; a double-tap re-reads the request inside the same Postgres
  // transaction the RPC runs as, same no-op-if-already-resolved guarantee
  // the Firestore version had.
  Future<void> _approve() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await Supabase.instance.client
          .rpc('approve_club_request', params: {'p_request_id': widget.requestId});

      AppHaptics.confirm();
      messenger.showSnackBar(const SnackBar(content: Text('Club approved successfully')));
    } catch (e) {
      messenger.showSnackBar(const SnackBar(content: Text('Approval failed. Try again.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await Supabase.instance.client
          .from('club_requests')
          .update({'status': 'rejected'})
          .eq('id', widget.requestId);
    } catch (e) {
      messenger.showSnackBar(const SnackBar(content: Text('Reject failed. Try again.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    return RequestCard(
      title: data['club_name'] ?? '',
      busy: _busy,
      extras: [
        if ((data['description'] ?? '').toString().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(data['description'], style: Theme.of(context).textTheme.bodyMedium),
          ),
        Text('Phone: ${data['phone']}', style: Theme.of(context).textTheme.bodySmall),
        Text('USN: ${data['usn']}', style: Theme.of(context).textTheme.bodySmall),
        if (data['id_card_url'] != null) ...[
          const SizedBox(height: AppSpace.md),
          _IdCardPreview(path: data['id_card_url']),
        ],
      ],
      secondaryLabel: 'Reject',
      onSecondary: _reject,
      primaryLabel: 'Approve',
      onPrimary: _approve,
    );
  }
}

/// The `clubs` bucket is private (ID card photos are personal documents;
/// see storage RLS in 20260914000012_clubs_bucket_private.sql), so
/// `data['id_card_url']` is a storage path, not a fetchable URL. A signed
/// URL is minted on demand, scoped to this admin's session, and expires
/// shortly after -- never persisted or shown to anyone but the admin
/// viewing this screen right now.
class _IdCardPreview extends StatelessWidget {
  final String path;
  const _IdCardPreview({required this.path});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: Supabase.instance.client.storage
          .from('clubs')
          .createSignedUrl(path, 300),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Skeleton(
            height: 160,
            borderRadius: BorderRadius.all(Radius.circular(AppRadius.sm)),
          );
        }
        if (snap.hasError || !snap.hasData) {
          return const Center(
            child: Text('Unable to load ID card', style: TextStyle(color: AppColors.textMuted)),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Image.network(
            snap.data!,
            height: 160,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) {
              return const Center(
                child: Text('Unable to load ID card', style: TextStyle(color: AppColors.textMuted)),
              );
            },
          ),
        );
      },
    );
  }
}
