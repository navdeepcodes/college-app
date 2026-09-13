import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../profile/profile_screen.dart';
import '../auth/services/college_detector.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

enum _LoadState { loading, error, noProfile, ready }

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  String _query = '';

  _LoadState _state = _LoadState.loading;
  List<Map<String, dynamic>> _directory = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  // The directory is college-scoped and loaded ONCE (not a live listener
  // rebuilt on every keystroke — the previous version inlined the query
  // directly in build(), which re-subscribed a fresh listener on the
  // entire college's user collection every time _query changed, i.e. on
  // every character typed). Filtering happens in-memory below.
  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final userDoc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();

      final collegeId = canonicalCollegeId(userDoc.data());
      if (collegeId.isEmpty) {
        if (mounted) setState(() => _state = _LoadState.noProfile);
        return;
      }

      // The Firestore rules reject an unfiltered users query (see
      // firestore.rules users block), so this where() is mandatory, not a
      // convenience. Capped: a college directory search doesn't need to
      // hold every profile in memory at once.
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('collegeId', isEqualTo: collegeId)
          .limit(1000)
          .get();

      if (!mounted) return;
      setState(() {
        _directory =
            snap.docs.map((d) => d.data()).toList(growable: false);
        _state = _LoadState.ready;
      });
    } catch (_) {
      if (mounted) setState(() => _state = _LoadState.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: Column(
        children: [
          // 🔍 SEARCH BAR
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: 'Search classmates',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _query = value.trim().toLowerCase();
                });
              },
            ),
          ),

          // 👥 RESULTS (college-isolated)
          Expanded(child: _buildResults()),
        ],
      ),
    );
  }

  Widget _buildResults() {
    switch (_state) {
      case _LoadState.loading:
        return const Center(child: CircularProgressIndicator());
      case _LoadState.error:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Failed to load classmates',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        );
      case _LoadState.noProfile:
        return const Center(
          child: Text(
            'Complete your profile to search classmates',
            style: TextStyle(color: Colors.white70),
          ),
        );
      case _LoadState.ready:
        break;
    }

    if (_query.isEmpty) {
      return const Center(
        child: Text(
          'Start typing to search',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }

    final users = _directory.where((user) {
      final name = (user['name'] ?? '').toString().toLowerCase();
      return name.contains(_query);
    }).toList();

    if (users.isEmpty) {
      return const Center(
        child: Text(
          'No users found',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }

    return ListView.builder(
      itemCount: users.length,
      itemBuilder: (context, index) {
        final user = users[index];

        return ListTile(
          leading: CircleAvatar(
            backgroundImage: user['photoUrl'] != null
                ? NetworkImage(user['photoUrl'])
                : null,
            child: user['photoUrl'] == null
                ? const Icon(Icons.person)
                : null,
          ),
          title: Text(user['name'] ?? ''),
          subtitle: Text(
            '${user['college'] ?? ''} ${user['year'] ?? ''}',
          ),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProfileScreen(userId: user['uid']),
              ),
            );
          },
        );
      },
    );
  }
}
