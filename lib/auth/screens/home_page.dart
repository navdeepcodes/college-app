import 'package:flutter/material.dart';

import '../../feed/feed_screen.dart';
import '../../feed/add_post_screen.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Campus'),
        actions: [
          // ➕ ADD POST
          IconButton(
            icon: const Icon(Icons.add_box_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AddPostScreen(),
                ),
              );
            },
          ),

          // 💬 MESSAGES
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline),
            onPressed: () {
              // messages later
            },
          ),

          // 🔔 NOTIFICATIONS
          IconButton(
            icon: const Icon(Icons.notifications_none),
            onPressed: () {
              // notifications later
            },
          ),
        ],
      ),

      // 🔽 FEED (BODY ONLY)
      body: SafeArea(
        top: false,
        child: FeedScreen(), // ❌ NOT const
      ),
    );
  }
}