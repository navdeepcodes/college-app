import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'chat_screen.dart';
import 'start_conversation_screen.dart';

class ChatsListScreen extends StatelessWidget {
  const ChatsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = Supabase.instance.client.auth.currentUser!.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Messages',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
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
            return const Center(child: Text('Failed to load messages'));
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
            return const _EmptyMessagesState();
          }

          return ListView.separated(
            itemCount: chats.length,
            separatorBuilder: (_, __) => const Divider(indent: 72),
            itemBuilder: (context, index) {
              final data = chats[index];
              final peerUid =
                  data['user_a'] == uid ? data['user_b'] as String : data['user_a'] as String;

              return _ChatTile(
                peerUid: peerUid,
                lastMessage: data['last_message'] ?? '',
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

  const _ChatTile({
    required this.peerUid,
    required this.lastMessage,
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
            leading: CircleAvatar(),
            title: Text('Loading...'),
          );
        }

        if (snap.data!.isEmpty) return const SizedBox.shrink();
        final user = snap.data!.first;

        return ListTile(
          leading: CircleAvatar(
            radius: 24,
            backgroundImage: user['photo_url'] != null
                ? NetworkImage(user['photo_url'])
                : null,
            child: user['photo_url'] == null
                ? const Icon(Icons.person)
                : null,
          ),
          title: Text(
            user['name'] ?? 'User',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            lastMessage.isEmpty ? 'Tap to chat' : lastMessage,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
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

class _EmptyMessagesState extends StatelessWidget {
  const _EmptyMessagesState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 64),
          SizedBox(height: 12),
          Text(
            'No conversations yet',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
