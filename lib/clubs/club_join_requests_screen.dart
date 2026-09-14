import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/dedupe_stream_rows.dart';
import '../core/app_colors.dart';
import '../core/haptics.dart';
import '../core/widgets/avatar.dart';
import '../core/widgets/empty_state.dart';
import '../core/widgets/entrance.dart';
import '../core/widgets/request_card.dart';

class ClubJoinRequestsScreen extends StatelessWidget {
  final String clubId;

  const ClubJoinRequestsScreen({
    super.key,
    required this.clubId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Join requests')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: Supabase.instance.client
            .from('club_join_requests')
            .stream(primaryKey: ['id'])
            .eq('club_id', clubId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final pending = dedupeStreamRowsById(snap.data ?? [])
              .where((r) => r['status'] == 'pending')
              .toList();

          if (pending.isEmpty) {
            return const EmptyState(
              icon: Icons.inbox_outlined,
              title: 'No pending requests',
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            itemCount: pending.length,
            itemBuilder: (context, index) {
              final data = pending[index];

              return Entrance(
                key: ValueKey(data['id']),
                delay: Duration(milliseconds: 30 * index),
                child: _RequestCardWrapper(
                  requestId: data['id'] as String,
                  clubId: clubId,
                  userId: data['user_id'] as String,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _RequestCardWrapper extends StatefulWidget {
  final String requestId;
  final String clubId;
  final String userId;

  const _RequestCardWrapper({
    required this.requestId,
    required this.clubId,
    required this.userId,
  });

  @override
  State<_RequestCardWrapper> createState() => _RequestCardWrapperState();
}

class _RequestCardWrapperState extends State<_RequestCardWrapper> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', widget.userId)
          .limit(1),
      builder: (context, userSnap) {
        if (!userSnap.hasData) {
          return const SizedBox(height: 80);
        }

        if (userSnap.data!.isEmpty) return const SizedBox();
        final user = userSnap.data!.first;
        final name = user['name'] ?? 'Student';

        return RequestCard(
          leading: AppAvatar(photoUrl: user['photo_url'], name: name, radius: 22),
          title: name,
          subtitle: '${user['branch'] ?? ''} · ${user['year'] ?? ''}',
          busy: _busy,
          secondaryLabel: 'Reject',
          onSecondary: () => _reject(context),
          primaryLabel: 'Approve',
          primaryColor: AppColors.success,
          onPrimary: () => _approve(context),
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
        params: {'p_request_id': widget.requestId},
      );

      AppHaptics.confirm();
      messenger.showSnackBar(const SnackBar(content: Text('Member approved')));
    } catch (e) {
      messenger.showSnackBar(const SnackBar(content: Text('Approval failed. Try again.')));
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
          .eq('id', widget.requestId);

      messenger.showSnackBar(const SnackBar(content: Text('Request rejected')));
    } catch (e) {
      messenger.showSnackBar(const SnackBar(content: Text('Reject failed. Try again.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
