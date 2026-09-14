import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app/auth_gate.dart';
import '../clubs/admin_club_requests_screen.dart';
import '../moderation/reports_admin_screen.dart';
import '../profile/edit_profile_screen.dart';
import '../core/app_colors.dart';
import '../core/spacing.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUid = Supabase.instance.client.auth.currentUser?.id;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
        children: [
          const _SectionLabel('Account'),
          _SettingsTile(
            icon: Icons.person_outline_rounded,
            title: 'Account',
            subtitle: 'Name, bio, photo',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const EditProfileScreen()),
            ),
          ),
          const _SettingsTile(
            icon: Icons.lock_outline_rounded,
            title: 'Privacy',
            trailing: _SoonChip(),
          ),

          const _SectionLabel('Anonymous'),
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

              return _SettingsTile(
                icon: Icons.visibility_off_outlined,
                title: 'Your anonymous ID',
                subtitle: 'Fixed and cannot be changed',
                trailing: Text(
                  anonId,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                    color: AppColors.accentBright,
                  ),
                ),
              );
            },
          ),

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
                  const _SectionLabel('Admin'),
                  _SettingsTile(
                    icon: Icons.approval_outlined,
                    title: 'Club requests',
                    subtitle: 'Approve / reject clubs',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AdminClubRequestsScreen()),
                    ),
                  ),
                  _SettingsTile(
                    icon: Icons.flag_outlined,
                    title: 'Reports',
                    subtitle: 'Review flagged content and users',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ReportsAdminScreen()),
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: AppSpace.lg),
          const Divider(indent: 20, endIndent: 20),
          _SettingsTile(
            icon: Icons.logout_rounded,
            title: 'Log out',
            iconColor: AppColors.danger,
            titleColor: AppColors.danger,
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

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: AppColors.textMuted,
        ),
      ),
    );
  }
}

class _SoonChip extends StatelessWidget {
  const _SoonChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.border),
      ),
      child: const Text(
        'Soon',
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.textMuted),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Color? iconColor;
  final Color? titleColor;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.iconColor,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: (iconColor ?? AppColors.textSecondary).withValues(alpha: 0.12),
        ),
        child: Icon(icon, size: 19, color: iconColor ?? AppColors.textSecondary),
      ),
      title: Text(title, style: titleColor != null ? TextStyle(color: titleColor) : null),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      trailing: trailing ?? (onTap != null ? const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted) : null),
      onTap: onTap,
      enabled: onTap != null,
    );
  }
}
