import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../chat/chat_screen.dart';
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
            return const Center(child: Text('Failed to load friends'));
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
            return const Center(child: Text('No friends yet'));
          }

          return ListView.builder(
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

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: user['photo_url'] != null
                          ? NetworkImage(user['photo_url'])
                          : null,
                      child: user['photo_url'] == null
                          ? const Icon(Icons.person)
                          : null,
                    ),
                    title: Text(user['name'] ?? ''),
                    subtitle: Text(user['college'] ?? ''),
                    trailing: IconButton(
                      icon: const Icon(Icons.chat),
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
