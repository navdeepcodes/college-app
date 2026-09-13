import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminClubRequestsScreen extends StatelessWidget {
  const AdminClubRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Club Creation Requests'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('club_requests')
            .where('status', isEqualTo: 'pending')
            .snapshots(),
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

          final docs = snap.data?.docs ?? [];

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
              final doc = docs[index];
              return _ClubRequestCard(
                requestId: doc.id,
                data: doc.data() as Map<String, dynamic>,
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

  // ================= APPROVE =================
  // Runs as a single transaction so a double-tap (or a re-render firing the
  // callback twice) can't create two clubs docs: the transaction re-reads
  // the request fresh and only proceeds if it's still 'pending', flipping
  // the status in the same atomic write as club creation.
  Future<void> _approve() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);

    final firestore = FirebaseFirestore.instance;
    final requestRef = firestore.collection('club_requests').doc(widget.requestId);
    final clubRef = firestore.collection('clubs').doc();
    final ownerUid = widget.data['ownerUid'];

    try {
      await firestore.runTransaction((txn) async {
        final freshRequest = await txn.get(requestRef);
        if (!freshRequest.exists || freshRequest.data()?['status'] != 'pending') {
          // Already approved/rejected by a concurrent action — no-op.
          return;
        }

        txn.set(clubRef, {
          'name': widget.data['clubName'],
          'description': widget.data['description'],
          'ownerUid': ownerUid,
          'admins': [ownerUid],
          'membersCount': 1,
          'createdAt': FieldValue.serverTimestamp(),
        });

        txn.set(
          firestore.collection('club_members').doc('${clubRef.id}_$ownerUid'),
          {
            'clubId': clubRef.id,
            'userId': ownerUid,
            'role': 'admin',
            'joinedAt': FieldValue.serverTimestamp(),
          },
        );

        txn.update(requestRef, {'status': 'approved'});
      });

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

  // ================= REJECT =================
  Future<void> _reject() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await FirebaseFirestore.instance
          .collection('club_requests')
          .doc(widget.requestId)
          .update({'status': 'rejected'});
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
              data['clubName'] ?? '',
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

            // ID CARD
            if (data['idCardUrl'] != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  data['idCardUrl'],
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
              ),

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
