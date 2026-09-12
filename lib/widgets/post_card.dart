import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PostCard extends StatelessWidget {
  final String postId;
  final Map<String, dynamic> data;

  const PostCard({
    super.key,
    required this.postId,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (data['imageUrl'] != null)
          Image.network(
            data['imageUrl'],
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(data['text'] ?? ''),
        ),
        const Divider(color: Colors.white12),
      ],
    );
  }
}