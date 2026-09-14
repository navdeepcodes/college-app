import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_colors.dart';
import '../core/widgets/avatar.dart';
import '../core/widgets/empty_state.dart';
import '../core/widgets/relative_time.dart';
import 'chat_screen.dart';
import 'start_conversation_screen.dart';

class ChatsListScreen extends StatelessWidget {
  const ChatsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = Supabase.instance.client.auth.currentUser!.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_square),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const StartConversationScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: Supabase.instance.client
            .from('conversations')
            .stream(primaryKey: ['id'])
            .order('last_message_at', ascending: false),
        builder: (context, snap) {
          if (snap.hasError) {
            return const EmptyState(
              icon: Icons.error_outline_rounded,
              title: "Couldn't load messages",
              isError: true,
            );
          }

          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          // RLS already scopes the stream to conversations we're a member
          // of (conversations_select: auth.uid() in (user_a, user_b)) --
          // this filter just narrows out any transient extra rows and
          // makes the membership check explicit for peerUid below.
          final chats = (snap.data ?? [])
              .where((c) => c['user_a'] == uid || c['user_b'] == uid)
              .toList();

          if (chats.isEmpty) {
            return const EmptyState(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'No conversations yet',
              message: 'Messages with your friends will show up here.',
            );
          }

          return ListView.separated(
            itemCount: chats.length,
            separatorBuilder: (_, __) => const Divider(indent: 76, height: 1),
            itemBuilder: (context, index) {
              final data = chats[index];
              final peerUid =
                  data['user_a'] == uid ? data['user_b'] as String : data['user_a'] as String;
              final lastMessageAtRaw = data['last_message_at'] as String?;
              final lastMessageAt =
                  lastMessageAtRaw != null ? DateTime.tryParse(lastMessageAtRaw) : null;

              return _ChatTile(
                peerUid: peerUid,
                lastMessage: data['last_message'] ?? '',
                lastMessageAt: lastMessageAt,
              );
            },
          );
        },
      ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  final String peerUid;
  final String lastMessage;
  final DateTime? lastMessageAt;

  const _ChatTile({
    required this.peerUid,
    required this.lastMessage,
    required this.lastMessageAt,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', peerUid)
          .limit(1),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const ListTile(
            leading: CircleAvatar(backgroundColor: AppColors.surfaceSunken),
            title: Text('Loading...'),
          );
        }

        if (snap.data!.isEmpty) return const SizedBox.shrink();
        final user = snap.data!.first;
        final name = user['name'] ?? 'User';

        return ListTile(
          leading: AppAvatar(photoUrl: user['photo_url'], name: name, radius: 24),
          title: Text(name),
          subtitle: Text(
            lastMessage.isEmpty ? 'Tap to chat' : lastMessage,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: lastMessageAt != null
              ? Text(
                  relativeTime(lastMessageAt!),
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                )
              : null,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatScreen(peerUid: peerUid),
              ),
            );
          },
        );
      },
    );
  }
}
