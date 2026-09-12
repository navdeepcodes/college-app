import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'college_anon_chat_screen.dart';

class AnonHomeScreen extends StatefulWidget {
  const AnonHomeScreen({super.key});

  @override
  State<AnonHomeScreen> createState() => _AnonHomeScreenState();
}

class _AnonHomeScreenState extends State<AnonHomeScreen> {
  String? _collegeId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    _collegeId = snap.data()?['collegeId'];

    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _collegeId == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.deepPurple),
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
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),

      // 🔥 CREATE GROUP BUTTON
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.deepPurple,
        icon: const Icon(Icons.add),
        label: const Text('Create group'),
        onPressed: _openCreateGroup,
      ),

      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
        children: [
          // ================= HEADER =================
          const Text(
            'Speak freely.',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'No names. No profiles. Just people.',
            style: TextStyle(color: Colors.white54),
          ),

          const SizedBox(height: 28),

          // ================= COLLEGE GROUP =================
          const _SectionTitle('College'),

          _AnonGroupCard(
            title: 'Your College Anon',
            subtitle: 'Everyone in your college',
            icon: Icons.school_rounded,
            highlight: true,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CollegeAnonChatScreen(
                    chatId: 'college_$_collegeId',
                    chatName: 'Your College Anon',
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 32),

          // ================= PRIVATE GROUPS =================
          const _SectionTitle('Your groups'),

          _EmptyPrivateGroups(),
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
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Create anonymous group',
              style: TextStyle(
                fontSize: 18,
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
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () {
                Navigator.pop(context);
                // 🔜 creation logic already exists elsewhere
              },
              child: const Text('Create'),
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
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          letterSpacing: 1.4,
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
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: highlight
              ? Colors.deepPurple.withOpacity(0.15)
              : const Color(0xFF1C1C1E),
          border: Border.all(
            color: highlight
                ? Colors.deepPurple.withOpacity(0.4)
                : Colors.white.withOpacity(0.06),
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor:
              highlight ? Colors.deepPurple : const Color(0xFF2A2A2E),
              child: Icon(icon, color: Colors.white),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      )),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: const TextStyle(color: Colors.white60)),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: Colors.white38,
            ),
          ],
        ),
      ),
    );
  }
}

// ================= EMPTY PRIVATE GROUPS =================

class _EmptyPrivateGroups extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28),
      alignment: Alignment.center,
      child: const Text(
        'No private groups yet\nCreate one to start chatting',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white38),
      ),
    );
  }
}