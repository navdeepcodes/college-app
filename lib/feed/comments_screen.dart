import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../moderation/text_filter.dart';
import '../utils/dedupe_stream_rows.dart';
import '../core/app_colors.dart';
import '../core/spacing.dart';
import '../core/widgets/avatar.dart';
import '../core/widgets/empty_state.dart';
import '../core/widgets/entrance.dart';

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

    final filterResult = TextFilter.filter(text);
    if (!filterResult.isAllowed) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Comment blocked by filter')),
        );
      }
      return;
    }

    setState(() => _sending = true);

    try {
      final supabase = Supabase.instance.client;
      final uid = supabase.auth.currentUser!.id;

      // comments_count is trigger-maintained (bump_post_comments_count) --
      // a single insert here, no batch/increment needed the way the
      // Firestore version had to pair a write with a counter update.
      await supabase.from('comments').insert({
        'post_id': widget.postId,
        'user_id': uid,
        'text': filterResult.cleanedText,
      });

      _controller.clear();
    } catch (e) {
      debugPrint('Comment send failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Comment not sent. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final supabase = Supabase.instance.client;
    return Scaffold(
      appBar: AppBar(title: const Text('Comments')),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: supabase
                  .from('comments')
                  .stream(primaryKey: ['id'])
                  .eq('post_id', widget.postId)
                  .order('created_at', ascending: false)
                  .limit(200),
              builder: (context, snap) {
                if (snap.hasError) {
                  return const EmptyState(
                    icon: Icons.error_outline_rounded,
                    title: "Couldn't load comments",
                    isError: true,
                  );
                }

                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final comments = dedupeStreamRowsById(snap.data!);

                if (comments.isEmpty) {
                  return const EmptyState(
                    icon: Icons.mode_comment_outlined,
                    title: 'No comments yet',
                    message: 'Say something first.',
                  );
                }

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
                  itemCount: comments.length,
                  itemBuilder: (context, index) {
                    final data = comments[index];
                    return Entrance(
                      key: ValueKey(data['id']),
                      child: _CommentTile(
                        userId: data['user_id'],
                        text: data['text'],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Add a comment...',
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded, color: AppColors.accentBright),
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

class _CommentTile extends StatelessWidget {
  final String userId;
  final String text;

  const _CommentTile({
    required this.userId,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', userId)
          .limit(1),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final user = snap.data!.first;
        final name = user['name'] ?? 'User';
        final photoUrl = user['photo_url'];

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppAvatar(photoUrl: photoUrl, name: name, radius: 16),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                    const SizedBox(height: 2),
                    Text(text, style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
