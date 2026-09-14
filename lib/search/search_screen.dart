import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../profile/profile_screen.dart';
import '../auth/services/college_detector.dart';
import '../core/spacing.dart';
import '../core/widgets/avatar.dart';
import '../core/widgets/empty_state.dart';

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

  // The directory is college-scoped and loaded ONCE (not re-queried on
  // every keystroke — same discipline as the Firestore version, which
  // fixed a per-keystroke full-directory re-subscribe bug). Filtering
  // happens in-memory below.
  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);

    try {
      final supabase = Supabase.instance.client;
      final uid = supabase.auth.currentUser!.id;
      final profileRows =
          await supabase.from('profiles').select().eq('id', uid).limit(1);

      final collegeId = profileRows.isNotEmpty
          ? canonicalCollegeId(profileRows.first)
          : '';
      if (collegeId.isEmpty) {
        if (mounted) setState(() => _state = _LoadState.noProfile);
        return;
      }

      // RLS rejects an unfiltered profiles query (profiles_select requires
      // own-row-or-same-college-or-admin) the same way the Firestore rule
      // did, so this eq() is mandatory, not a convenience.
      final rows = await supabase
          .from('profiles')
          .select()
          .eq('college_id', collegeId)
          .limit(1000);

      if (!mounted) return;
      setState(() {
        _directory = rows;
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
          Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: TextField(
              controller: _controller,
              decoration: const InputDecoration(
                hintText: 'Search classmates',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (value) {
                setState(() {
                  _query = value.trim().toLowerCase();
                });
              },
            ),
          ),
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
        return EmptyState.error(onAction: _load);
      case _LoadState.noProfile:
        return const EmptyState(
          icon: Icons.badge_outlined,
          title: 'Finish your profile',
          message: 'Complete your profile to search classmates.',
        );
      case _LoadState.ready:
        break;
    }

    if (_query.isEmpty) {
      return const EmptyState(
        icon: Icons.search_rounded,
        title: 'Start typing to search',
      );
    }

    final users = _directory.where((user) {
      final name = (user['name'] ?? '').toString().toLowerCase();
      return name.contains(_query);
    }).toList();

    if (users.isEmpty) {
      return const EmptyState(
        icon: Icons.person_search_outlined,
        title: 'No users found',
        message: 'Try a different name.',
      );
    }

    return ListView.builder(
      itemCount: users.length,
      itemBuilder: (context, index) {
        final user = users[index];
        final name = user['name'] ?? '';

        return ListTile(
          leading: AppAvatar(photoUrl: user['photo_url'], name: name, radius: 22),
          title: Text(name),
          subtitle: Text(
            '${user['college'] ?? ''} ${user['year'] ?? ''}',
          ),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProfileScreen(userId: user['id']),
              ),
            );
          },
        );
      },
    );
  }
}
