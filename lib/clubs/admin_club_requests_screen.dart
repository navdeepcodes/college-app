import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminClubRequestsScreen extends StatelessWidget {
  const AdminClubRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Club Creation Requests'),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: Supabase.instance.client
            .from('club_requests')
            .stream(primaryKey: ['id'])
            .eq('status', 'pending'),
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(
              child: Text(
                'Failed to load club requests',
                style: TextStyle(color: Colors.white54),
              ),
            );
          }

          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snap.data ?? [];

          if (docs.isEmpty) {
            return const Center(
              child: Text(
                'No pending club requests',
                style: TextStyle(color: Colors.white54),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index];
              return _ClubRequestCard(
                requestId: data['id'] as String,
                data: data,
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

      messenger.showSnackBar(
        const SnackBar(content: Text('Club approved successfully')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Approval failed: $e')),
      );
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
      messenger.showSnackBar(
        SnackBar(content: Text('Reject failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              data['club_name'] ?? '',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(data['description'] ?? ''),
            const SizedBox(height: 8),
            Text('Phone: ${data['phone']}'),
            Text('USN: ${data['usn']}'),
            const SizedBox(height: 12),
            if (data['id_card_url'] != null) _IdCardPreview(path: data['id_card_url']),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : _reject,
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _busy ? null : _approve,
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Approve'),
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
          return const SizedBox(
            height: 160,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError || !snap.hasData) {
          return const Center(
            child: Text(
              'Unable to load ID card',
              style: TextStyle(color: Colors.white54),
            ),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            snap.data!,
            height: 160,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) {
              return const Center(
                child: Text(
                  'Unable to load ID card',
                  style: TextStyle(color: Colors.white54),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
