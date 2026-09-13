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

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
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
          Expanded(
            // The directory is college-scoped: resolve the caller's canonical
            // collegeId, then only query that college's profiles. The Firestore
            // rules reject an unfiltered users query (see firestore.rules
            // users block), so the `where('collegeId')` below is mandatory, not
            // a convenience.
            child: FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .get(),
              builder: (context, userSnap) {
                final collegeId = userSnap.hasData
                    ? canonicalCollegeId(
                        userSnap.data!.data() as Map<String, dynamic>?)
                    : '';
                if (collegeId.isEmpty) {
                  return const Center(
                    child: Text(
                      'Complete your profile to search classmates',
                      style: TextStyle(color: Colors.white70),
                    ),
                  );
                }

                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .where('collegeId', isEqualTo: collegeId)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(
                          child: CircularProgressIndicator());
                    }

                    final users = snapshot.data!.docs
                        .map((doc) => doc.data() as Map<String, dynamic>)
                        .where((user) {
                      final name =
                          (user['name'] ?? '').toString().toLowerCase();
                      return name.contains(_query);
                    }).toList();

                    if (_query.isNotEmpty && users.isEmpty) {
                      return const Center(
                        child: Text(
                          'No users found',
                          style: TextStyle(color: Colors.white54),
                        ),
                      );
                    }

                    if (_query.isEmpty) {
                      return const Center(
                        child: Text(
                          'Start typing to search',
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
                          title: Text(user['name']),
                          subtitle: Text(
                            '${user['college'] ?? ''} ${user['year'] ?? ''}',
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ProfileScreen(
                                  userId: user['uid'],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}