import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../clubs/admin_club_requests_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUid = Supabase.instance.client.auth.currentUser?.id;

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

          StreamBuilder<List<Map<String, dynamic>>>(
            stream: Supabase.instance.client
                .from('profiles')
                .stream(primaryKey: ['id'])
                .eq('id', currentUid ?? '')
                .limit(1),
            builder: (context, snap) {
              if (!snap.hasData || snap.data!.isEmpty) {
                return const SizedBox.shrink();
              }

              final data = snap.data!.first;
              final anonId = data['anon_id'];

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
          // Firebase's adminUid was a compile-time constant
          // (lib/core/admin.dart); Supabase has no equivalent identity to
          // hardcode (Firebase UIDs and Supabase UUIDs are different
          // spaces — see docs/supabase-auth-migration.md), so admin
          // status is a live profiles.is_admin lookup instead.
          FutureBuilder<List<Map<String, dynamic>>>(
            future: currentUid == null
                ? Future.value(const [])
                : Supabase.instance.client
                    .from('profiles')
                    .select('is_admin')
                    .eq('id', currentUid)
                    .limit(1),
            builder: (context, snap) {
              final isAdmin = (snap.data ?? []).isNotEmpty &&
                  snap.data!.first['is_admin'] == true;

              if (!isAdmin) return const SizedBox.shrink();

              return Column(
                children: [
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
                          builder: (_) => const AdminClubRequestsScreen(),
                        ),
                      );
                    },
                  ),
                  const Divider(),
                ],
              );
            },
          ),

          // ================= LOGOUT =================
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Log out'),
            onTap: () async {
              await Supabase.instance.client.auth.signOut();
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
