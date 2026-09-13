import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../moderation/text_filter.dart';

class CommentsScreen extends StatefulWidget {
  final String postId;

  const CommentsScreen({super.key, required this.postId});

  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen> {
  final _controller = TextEditingController();
  bool _sending = false;

  Future<void> _sendComment() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    // Moderation: block comments the content filter rejects (anon-chat policy).
    final filterResult = TextFilter.filter(text);
    if (!filterResult.isAllowed) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠️ Comment blocked by filter')),
        );
      }
      return;
    }

    setState(() => _sending = true);

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final postRef =
      FirebaseFirestore.instance.collection('posts').doc(widget.postId);
      final commentRef = postRef.collection('comments').doc();

      // Batched so a dropped connection between the two writes can't leave
      // commentsCount permanently undercounting the actual comment docs.
      final batch = FirebaseFirestore.instance.batch();
      batch.set(commentRef, {
        'userId': uid,
        'text': filterResult.cleanedText,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.update(postRef, {
        'commentsCount': FieldValue.increment(1),
      });
      await batch.commit();

      _controller.clear();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Comment not sent. Try again.'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Comments'),
        backgroundColor: Colors.black,
        elevation: 0,
      ),
      body: Column(
        children: [
          /// COMMENTS LIST
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('posts')
                  .doc(widget.postId)
                  .collection('comments')
                  .orderBy('createdAt', descending: true)
                  .limit(200)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return const Center(
                    child: Text(
                      'Failed to load comments',
                      style: TextStyle(color: Colors.white70),
                    ),
                  );
                }

                if (!snap.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                if (snap.data!.docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'No comments yet',
                      style: TextStyle(color: Colors.white70),
                    ),
                  );
                }

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: snap.data!.docs.length,
                  itemBuilder: (context, index) {
                    final data = snap.data!.docs[index].data()
                    as Map<String, dynamic>;
                    return _CommentTile(
                      userId: data['userId'],
                      text: data['text'],
                    );
                  },
                );
              },
            ),
          ),

          /// INPUT BAR
          SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black,
                border: Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Add a comment...',
                        hintStyle:
                        TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.06),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: _sending
                        ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Icon(Icons.send, color: Colors.deepPurple),
                    onPressed: _sending ? null : _sendComment,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// COMMENT TILE

class _CommentTile extends StatelessWidget {
  final String userId;
  final String text;

  const _CommentTile({
    required this.userId,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get(),
      builder: (context, snap) {
        if (!snap.hasData || !snap.data!.exists) {
          return const SizedBox.shrink();
        }

        final user = snap.data!.data() as Map<String, dynamic>;
        final name = user['name'] ?? 'User';
        final photoUrl = user['photoUrl'];

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.white24,
            backgroundImage:
            photoUrl != null ? NetworkImage(photoUrl) : null,
            child: photoUrl == null
                ? const Icon(Icons.person, size: 18)
                : null,
          ),
          title: Text(
            name,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          subtitle: Text(
            text,
            style: const TextStyle(color: Colors.white70),
          ),
        );
      },
    );
  }
}