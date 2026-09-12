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
              final data = doc.data() as Map<String, dynamic>;

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
                              onPressed: () => _reject(doc.id),
                              child: const Text('Reject'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () =>
                                  _approve(context, doc),
                              child: const Text('Approve'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // ================= APPROVE =================

  Future<void> _approve(
      BuildContext context,
      QueryDocumentSnapshot requestDoc,
      ) async {
    final data = requestDoc.data() as Map<String, dynamic>;
    final ownerUid = data['ownerUid'];

    final firestore = FirebaseFirestore.instance;

    // 1️⃣ CREATE CLUB
    final clubRef = await firestore.collection('clubs').add({
      'name': data['clubName'],
      'description': data['description'],
      'ownerUid': ownerUid,
      'admins': [ownerUid],
      'membersCount': 1,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // 2️⃣ ADD CREATOR AS ADMIN MEMBER
    await firestore
        .collection('club_members')
        .doc('${clubRef.id}_$ownerUid')
        .set({
      'clubId': clubRef.id,
      'userId': ownerUid,
      'role': 'admin',
      'joinedAt': FieldValue.serverTimestamp(),
    });

    // 3️⃣ UPDATE REQUEST STATUS
    await requestDoc.reference.update({'status': 'approved'});

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Club approved successfully')),
    );
  }

  // ================= REJECT =================

  Future<void> _reject(String requestId) async {
    await FirebaseFirestore.instance
        .collection('club_requests')
        .doc(requestId)
        .update({'status': 'rejected'});
  }
}