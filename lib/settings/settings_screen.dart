import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app/auth_gate.dart';
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

          // A plain one-time fetch, not .stream(): anonId never changes
          // after creation (see the "fixed and cannot be changed" copy
          // below), and lib/navigation/bottom_nav_shell.dart's
          // _ProfileNavIcon already holds a live .stream() on this same
          // table+filter for the whole time this screen is on top of it.
          // Two concurrent .stream() subscriptions with the identical
          // table/filter shape collide at the Realtime channel level --
          // confirmed live, on-device: the second one (this one) never
          // received its initial snapshot at all, so this section simply
          // never rendered, silently, for every account tested.
          FutureBuilder<List<Map<String, dynamic>>>(
            future: currentUid == null
                ? Future.value(const [])
                : Supabase.instance.client
                    .from('profiles')
                    .select()
                    .eq('id', currentUid)
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
            // A plain Navigator.pop(context) after signOut() raced
            // AuthGate's own StreamBuilder (app/auth_gate.dart), which
            // swaps the whole authenticated subtree for WelcomeScreen
            // only once onAuthStateChange actually delivers the
            // sign-out event -- an async step with no guaranteed
            // ordering against a synchronous pop right after the
            // signOut() Future resolves. Found live, on-device: the pop
            // sometimes won that race, revealing the *old* root route a
            // frame before AuthGate's rebuild landed -- and
            // BottomNavShell's build() reads auth.currentUser
            // synchronously with no recovery path if it's ever null, so
            // that frame became a permanently stuck loading spinner, not
            // a flicker.
            //
            // Push a *fresh* AuthGate and drop the entire old stack
            // instead of popping back into it. A new AuthGate's
            // StreamBuilder seeds its first frame from
            // `initialData: currentSession` -- read synchronously at
            // construction time, after signOut() has already fully
            // completed -- so it renders WelcomeScreen correctly on
            // its very first build. No dependency on when the stream
            // event arrives, so no race left to lose.
            onTap: () async {
              await Supabase.instance.client.auth.signOut();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const AuthGate()),
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
    );
  }
}
