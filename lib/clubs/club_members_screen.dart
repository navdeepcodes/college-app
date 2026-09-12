import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ClubMembersScreen extends StatelessWidget {
  final String clubId;

  const ClubMembersScreen({
    super.key,
    required this.clubId,
  });

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text('Members'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('club_members')
            .where('clubId', isEqualTo: clubId)
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
              final memberDoc = snap.data!.docs[index];
              final member = memberDoc.data() as Map<String, dynamic>;

              return _MemberTile(
                clubId: clubId,
                memberUid: member['userId'],
                role: member['role'] ?? 'member',
                currentUid: currentUid,
              );
            },
          );
        },
      ),
    );
  }
}

// =====================================================
// MEMBER TILE
// =====================================================

class _MemberTile extends StatelessWidget {
  final String clubId;
  final String memberUid;
  final String role;
  final String? currentUid;

  const _MemberTile({
    required this.clubId,
    required this.memberUid,
    required this.role,
    required this.currentUid,
  });

  @override
  Widget build(BuildContext context) {
    final isAdmin = role == 'admin';
    final isSelf = memberUid == currentUid;

    return FutureBuilder<DocumentSnapshot>(
      future:
      FirebaseFirestore.instance.collection('users').doc(memberUid).get(),
      builder: (context, userSnap) {
        if (!userSnap.hasData) {
          return const SizedBox(height: 72);
        }

        final user = userSnap.data!.data() as Map<String, dynamic>?;

        if (user == null) return const SizedBox();

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF151515),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
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

              if (isAdmin)
                const Text(
                  '👑',
                  style: TextStyle(fontSize: 18),
                ),

              if (_canManage(currentUid, clubId) && !isSelf)
                PopupMenuButton<String>(
                  color: const Color(0xFF1A1A1A),
                  onSelected: (value) {
                    if (value == 'promote') {
                      _promote(context);
                    } else if (value == 'remove') {
                      _remove(context);
                    }
                  },
                  itemBuilder: (_) => [
                    if (!isAdmin)
                      const PopupMenuItem(
                        value: 'promote',
                        child: Text('Make Admin'),
                      ),
                    const PopupMenuItem(
                      value: 'remove',
                      child: Text(
                        'Remove',
                        style: TextStyle(color: Colors.redAccent),
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
  // PERMISSIONS
  // =====================================================

  bool _canManage(String? uid, String clubId) {
    // UI-level guard (real guard is Firestore rules)
    return uid != null;
  }

  // =====================================================
  // ACTIONS
  // =====================================================

  Future<void> _promote(BuildContext context) async {
    await FirebaseFirestore.instance
        .collection('club_members')
        .doc('${clubId}_$memberUid')
        .update({'role': 'admin'});

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Promoted to admin')),
    );
  }

  Future<void> _remove(BuildContext context) async {
    final batch = FirebaseFirestore.instance.batch();

    batch.delete(
      FirebaseFirestore.instance
          .collection('club_members')
          .doc('${clubId}_$memberUid'),
    );

    batch.update(
      FirebaseFirestore.instance.collection('clubs').doc(clubId),
      {'membersCount': FieldValue.increment(-1)},
    );

    await batch.commit();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Member removed')),
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
    return const Center(
      child: Text(
        'No members yet',
        style: TextStyle(color: Colors.white54),
      ),
    );
  }
}