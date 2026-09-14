import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/dedupe_stream_rows.dart';

class ClubJoinRequestsScreen extends StatelessWidget {
  final String clubId;

  const ClubJoinRequestsScreen({
    super.key,
    required this.clubId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text('Join Requests'),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: Supabase.instance.client
            .from('club_join_requests')
            .stream(primaryKey: ['id'])
            .eq('club_id', clubId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.deepPurple),
            );
          }

          final pending = dedupeStreamRowsById(snap.data ?? [])
              .where((r) => r['status'] == 'pending')
              .toList();

          if (pending.isEmpty) {
            return const _EmptyState();
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            itemCount: pending.length,
            itemBuilder: (context, index) {
              final data = pending[index];

              return _RequestCard(
                requestId: data['id'] as String,
                clubId: clubId,
                userId: data['user_id'] as String,
              );
            },
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, size: 48, color: Colors.white24),
          SizedBox(height: 14),
          Text(
            'No pending requests',
            style: TextStyle(color: Colors.white54),
          ),
        ],
      ),
    );
  }
}

class _RequestCard extends StatefulWidget {
  final String requestId;
  final String clubId;
  final String userId;

  const _RequestCard({
    required this.requestId,
    required this.clubId,
    required this.userId,
  });

  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> {
  bool _busy = false;

  String get requestId => widget.requestId;
  String get userId => widget.userId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', userId)
          .limit(1),
      builder: (context, userSnap) {
        if (!userSnap.hasData) {
          return const SizedBox(height: 80);
        }

        if (userSnap.data!.isEmpty) return const SizedBox();
        final user = userSnap.data!.first;

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF151515),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundImage: user['photo_url'] != null
                        ? NetworkImage(user['photo_url'])
                        : null,
                    child: user['photo_url'] == null
                        ? const Icon(Icons.person, size: 20)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user['name'] ?? 'Student',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${user['branch'] ?? ''} • ${user['year'] ?? ''}',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _RejectButton(
                      onTap: _busy ? null : () => _reject(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ApproveButton(
                      busy: _busy,
                      onTap: _busy ? null : () => _approve(context),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _approve(BuildContext context) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await Supabase.instance.client.rpc(
        'approve_club_join_request',
        params: {'p_request_id': requestId},
      );

      messenger.showSnackBar(
        const SnackBar(content: Text('Member approved')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Approval failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject(BuildContext context) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await Supabase.instance.client
          .from('club_join_requests')
          .delete()
          .eq('id', requestId);

      messenger.showSnackBar(
        const SnackBar(content: Text('Request rejected')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Reject failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _ApproveButton extends StatelessWidget {
  final VoidCallback? onTap;
  final bool busy;

  const _ApproveButton({required this.onTap, this.busy = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: busy ? Colors.green.withValues(alpha: 0.5) : Colors.green,
          borderRadius: BorderRadius.circular(22),
        ),
        alignment: Alignment.center,
        child: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text(
                'Approve',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }
}

class _RejectButton extends StatelessWidget {
  final VoidCallback? onTap;

  const _RejectButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.redAccent),
        ),
        alignment: Alignment.center,
        child: const Text(
          'Reject',
          style: TextStyle(
            color: Colors.redAccent,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
