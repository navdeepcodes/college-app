import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'college_anon_chat_screen.dart';
import '../auth/services/college_detector.dart';

class AnonHomeScreen extends StatefulWidget {
  const AnonHomeScreen({super.key});

  @override
  State<AnonHomeScreen> createState() => _AnonHomeScreenState();
}

class _AnonHomeScreenState extends State<AnonHomeScreen> {
  String? _collegeId; // canonical college identity (collegeId, legacy fallback)
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    try {
      final user = FirebaseAuth.instance.currentUser;

      // ✅ Prevent Android auth race
      if (user == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!mounted) return;

      setState(() {
        _collegeId = canonicalCollegeId(snap.data());
        _loading = false;
      });
    } catch (e) {
      // ✅ Never allow infinite spinner
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.deepPurple),
        ),
      );
    }

    if (_collegeId == null || _collegeId!.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            'College not set',
            style: TextStyle(color: Colors.white54),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text(
          'Anonymous',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      ),

      // 🔥 FLOATING CREATE GROUP
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.deepPurple,
        elevation: 8,
        icon: const Icon(Icons.add),
        label: const Text(
          'Create group',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        onPressed: _openCreateGroup,
      ),

      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
        children: [
          // ================= HERO HEADER =================
          ShaderMask(
            shaderCallback: (rect) => LinearGradient(
              colors: [
                Colors.deepPurpleAccent,
                Colors.white.withValues(alpha: 0.9),
              ],
            ).createShader(rect),
            child: const Text(
              'Speak freely.',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'No names. No profiles. Just people.',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 15,
            ),
          ),

          const SizedBox(height: 36),

          // ================= COLLEGE =================
          const _SectionTitle('College'),

          _AnonGroupCard(
            title: 'Your College Anon',
            subtitle: 'Everyone from your campus',
            icon: Icons.school_rounded,
            highlight: true,
            onTap: () {
              final collegeId = _collegeId;
              if (collegeId == null || collegeId.isEmpty) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CollegeAnonChatScreen(
                    chatId: 'college_$collegeId',
                    chatName: 'Your College Anon',
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 40),

          // ================= PRIVATE GROUPS =================
          const _SectionTitle('Your groups'),
          const _EmptyPrivateGroups(),
        ],
      ),
    );
  }

  // ================= CREATE GROUP =================

  void _openCreateGroup() {
    final controller = TextEditingController();

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF121212),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Create anonymous group',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Group name',
                hintStyle: const TextStyle(color: Colors.white54),
                filled: true,
                fillColor: const Color(0xFF1C1C1E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 28),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              onPressed: () {
                Navigator.pop(context);
                // logic exists elsewhere
              },
              child: const Text(
                'Create',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================= SECTION TITLE =================

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          letterSpacing: 1.6,
          color: Colors.white38,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// ================= GROUP CARD =================

class _AnonGroupCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool highlight;

  const _AnonGroupCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: highlight
              ? LinearGradient(
            colors: [
              Colors.deepPurple.withValues(alpha: 0.25),
              Colors.deepPurple.withValues(alpha: 0.08),
            ],
          )
              : null,
          color: highlight ? null : const Color(0xFF1C1C1E),
          border: Border.all(
            color: highlight
                ? Colors.deepPurple.withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: highlight ? Colors.deepPurple : const Color(0xFF2A2A2E),
              ),
              child: Icon(icon, color: Colors.white),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white60),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}

// ================= EMPTY PRIVATE GROUPS =================

class _EmptyPrivateGroups extends StatelessWidget {
  const _EmptyPrivateGroups();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 36),
      child: Text(
        'No private groups yet\nCreate one to start chatting',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white38, height: 1.6),
      ),
    );
  }
}