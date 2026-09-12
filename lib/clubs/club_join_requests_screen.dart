import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('club_join_requests')
            .where('clubId', isEqualTo: clubId)
            .where('status', isEqualTo: 'pending')
        // ❌ REMOVED orderBy → fixes buffering
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.deepPurple),
            );
          }

          if (!snap.hasData || snap.data!.docs.isEmpty) {
            return const _EmptyState();
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            itemCount: snap.data!.docs.length,
            itemBuilder: (context, index) {
              final req = snap.data!.docs[index];
              final data = req.data() as Map<String, dynamic>;

              return _RequestCard(
                requestId: req.id,
                clubId: clubId,
                userId: data['userId'],
              );
            },
          );
        },
      ),
    );
  }
}

// =====================================================
// EMPTY STATE
// =====================================================

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
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

// =====================================================
// REQUEST CARD
// =====================================================

class _RequestCard extends StatelessWidget {
  final String requestId;
  final String clubId;
  final String userId;

  const _RequestCard({
    required this.requestId,
    required this.clubId,
    required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future:
      FirebaseFirestore.instance.collection('users').doc(userId).get(),
      builder: (context, userSnap) {
        if (!userSnap.hasData) {
          return const SizedBox(height: 80);
        }

        final user = userSnap.data!.data() as Map<String, dynamic>?;

        if (user == null) return const SizedBox();

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
              // USER INFO
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundImage: user['photoUrl'] != null
                        ? NetworkImage(user['photoUrl'])
                        : null,
                    child: user['photoUrl'] == null
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

              // ACTIONS
              Row(
                children: [
                  Expanded(
                    child: _RejectButton(
                      onTap: () => _reject(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ApproveButton(
                      onTap: () => _approve(context),
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

  // =====================================================
  // APPROVE
  // =====================================================

  Future<void> _approve(BuildContext context) async {
    final batch = FirebaseFirestore.instance.batch();

    final memberRef = FirebaseFirestore.instance
        .collection('club_members')
        .doc('${clubId}_$userId');

    final clubRef =
    FirebaseFirestore.instance.collection('clubs').doc(clubId);

    final requestRef = FirebaseFirestore.instance
        .collection('club_join_requests')
        .doc(requestId);

    batch.set(memberRef, {
      'clubId': clubId,
      'userId': userId,
      'role': 'member',
      'joinedAt': FieldValue.serverTimestamp(),
    });

    batch.update(clubRef, {
      'membersCount': FieldValue.increment(1),
    });

    batch.delete(requestRef);

    await batch.commit();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Member approved')),
    );
  }

  // =====================================================
  // REJECT
  // =====================================================

  Future<void> _reject(BuildContext context) async {
    await FirebaseFirestore.instance
        .collection('club_join_requests')
        .doc(requestId)
        .delete();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Request rejected')),
    );
  }
}

// =====================================================
// BUTTONS
// =====================================================

class _ApproveButton extends StatelessWidget {
  final VoidCallback onTap;

  const _ApproveButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: Colors.green,
          borderRadius: BorderRadius.circular(22),
        ),
        alignment: Alignment.center,
        child: const Text(
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
  final VoidCallback onTap;

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