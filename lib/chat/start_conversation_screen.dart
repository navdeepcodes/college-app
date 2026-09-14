import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/widgets/avatar.dart';
import '../core/widgets/empty_state.dart';
import 'chat_screen.dart';

class StartConversationScreen extends StatelessWidget {
  const StartConversationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUid = Supabase.instance.client.auth.currentUser!.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Start a conversation'),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        // RLS (friendships_select: auth.uid() in (user_a, user_b)) already
        // scopes this to our own friendships.
        stream: Supabase.instance.client
            .from('friendships')
            .stream(primaryKey: ['id']),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final friendRows = (snap.data ?? [])
              .where((f) => f['user_a'] == currentUid || f['user_b'] == currentUid)
              .toList();

          if (friendRows.isEmpty) {
            return const EmptyState(
              icon: Icons.people_outline_rounded,
              title: 'No friends yet',
              message: 'Add friends first, then start a chat with them here.',
            );
          }

          return ListView.builder(
            itemCount: friendRows.length,
            itemBuilder: (context, index) {
              final row = friendRows[index];
              final friendUid = row['user_a'] == currentUid
                  ? row['user_b'] as String
                  : row['user_a'] as String;

              return FutureBuilder<List<Map<String, dynamic>>>(
                future: Supabase.instance.client
                    .from('profiles')
                    .select()
                    .eq('id', friendUid)
                    .limit(1),
                builder: (context, userSnap) {
                  if (!userSnap.hasData || userSnap.data!.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  final user = userSnap.data!.first;

                  return ListTile(
                    leading: AppAvatar(
                      photoUrl: user['photo_url'],
                      name: user['name'] ?? 'User',
                      radius: 22,
                    ),
                    title: Text(user['name'] ?? 'User'),
                    subtitle: Text(
                      '${user['college'] ?? ''} • ${user['year'] ?? ''}',
                    ),
                    trailing: const Icon(Icons.chat_bubble_outline),
                    onTap: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(peerUid: friendUid),
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
