import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../clubs/admin_club_requests_screen.dart';
import '../core/admin.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 12),

          // ================= ACCOUNT =================
          const ListTile(
            leading: Icon(Icons.person),
            title: Text('Account'),
          ),
          const ListTile(
            leading: Icon(Icons.lock),
            title: Text('Privacy'),
          ),

          const Divider(),

          // ================= ANONYMOUS =================
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'ANONYMOUS',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white54,
                letterSpacing: 1.2,
              ),
            ),
          ),

          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(currentUid)
                .snapshots(),
            builder: (context, snap) {
              if (!snap.hasData || !snap.data!.exists) {
                return const SizedBox.shrink();
              }

              final data = snap.data!.data() as Map<String, dynamic>;
              final anonId = data['anonId'];

              if (anonId == null) return const SizedBox.shrink();

              return ListTile(
                leading: const Icon(Icons.visibility_off),
                title: const Text('Your Anonymous ID'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(
                      anonId,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'This ID is fixed and cannot be changed',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          const Divider(),

          // ================= ADMIN ONLY =================
          if (currentUid == adminUid) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'ADMIN',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white54,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.approval),
              title: const Text('Club Requests'),
              subtitle: const Text('Approve / Reject clubs'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                    const AdminClubRequestsScreen(),
                  ),
                );
              },
            ),
            const Divider(),
          ],

          // ================= LOGOUT =================
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Log out'),
            onTap: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
          ),
        ],
      ),
    );
  }
}