import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../chat/chat_screen.dart';
import '../core/widgets/avatar.dart';
import '../core/widgets/empty_state.dart';
import 'profile_screen.dart';

class FriendsListScreen extends StatelessWidget {
  final String userId;

  const FriendsListScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Friends')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        // user_a/user_b are OR'd via .or() since a friendship row could
        // have userId in either column (the sorted-pair constraint just
        // fixes WHICH column, not which side is "us").
        stream: Supabase.instance.client
            .from('friendships')
            .stream(primaryKey: ['id'])
            .order('created_at')
            .limit(500),
        builder: (context, snap) {
          if (snap.hasError) {
            return const EmptyState(
              icon: Icons.error_outline_rounded,
              title: "Couldn't load friends",
              isError: true,
            );
          }

          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final friendUids = snap.data!
              .where((row) => row['user_a'] == userId || row['user_b'] == userId)
              .map((row) => row['user_a'] == userId ? row['user_b'] as String : row['user_a'] as String)
              .toSet()
              .toList();

          if (friendUids.isEmpty) {
            return const EmptyState(
              icon: Icons.people_outline_rounded,
              title: 'No friends yet',
              message: 'Friends you add will show up here.',
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: friendUids.length,
            itemBuilder: (context, index) {
              final friendUid = friendUids[index];

              return StreamBuilder<List<Map<String, dynamic>>>(
                stream: Supabase.instance.client
                    .from('profiles')
                    .stream(primaryKey: ['id'])
                    .eq('id', friendUid)
                    .limit(1),
                builder: (context, userSnap) {
                  if (!userSnap.hasData || userSnap.data!.isEmpty) {
                    // Deleted/unavailable account — skip the row rather
                    // than crash on the null-cast below.
                    return const SizedBox.shrink();
                  }

                  final user = userSnap.data!.first;
                  final name = user['name'] ?? '';

                  return ListTile(
                    leading: AppAvatar(photoUrl: user['photo_url'], name: name, radius: 22),
                    title: Text(name),
                    subtitle: Text(user['college'] ?? ''),
                    trailing: IconButton(
                      icon: const Icon(Icons.chat_bubble_outline_rounded),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatScreen(peerUid: friendUid),
                          ),
                        );
                      },
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProfileScreen(userId: friendUid),
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
    );
  }
}
