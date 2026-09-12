import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../comments_screen.dart';

class PostCard extends StatefulWidget {
  final String postId;
  final Map<String, dynamic> data;

  const PostCard({
    super.key,
    required this.postId,
    required this.data,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _heartController;
  late Animation<double> _heartAnimation;
  bool _showHeart = false;

  @override
  void initState() {
    super.initState();

    _heartController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _heartAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(
        parent: _heartController,
        curve: Curves.easeOut,
      ),
    );

    _heartController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _heartController.reverse();
      } else if (status == AnimationStatus.dismissed) {
        setState(() => _showHeart = false);
      }
    });
  }

  @override
  void dispose() {
    _heartController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final postRef =
    FirebaseFirestore.instance.collection('posts').doc(widget.postId);
    final likeRef = postRef.collection('likes').doc(uid);
    final commentsRef = postRef.collection('comments');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ================= HEADER =================
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundImage: widget.data['userPhoto'] != null
                    ? NetworkImage(widget.data['userPhoto'])
                    : null,
                child: widget.data['userPhoto'] == null
                    ? const Icon(Icons.person, size: 18)
                    : null,
              ),
              const SizedBox(width: 10),
              Text(
                widget.data['userName'],
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              PopupMenuButton<String>(
                itemBuilder: (_) {
                  if (widget.data['userId'] == uid) {
                    return const [
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete'),
                      ),
                    ];
                  }
                  return const [
                    PopupMenuItem(
                      value: 'report',
                      child: Text('Report'),
                    ),
                  ];
                },
                onSelected: (value) async {
                  if (value == 'delete') {
                    await postRef.delete();
                  }
                },
              ),
            ],
          ),
        ),

        // ================= IMAGE + DOUBLE TAP =================
        if (widget.data['imageUrl'] != null)
          GestureDetector(
            onDoubleTap: () async {
              setState(() => _showHeart = true);
              _heartController.forward(from: 0);

              await FirebaseFirestore.instance
                  .runTransaction((tx) async {
                final postSnap = await tx.get(postRef);
                final likeSnap = await tx.get(likeRef);

                if (likeSnap.exists) return;

                final currentLikes =
                (postSnap['likesCount'] ?? 0) as int;

                tx.set(likeRef, {
                  'createdAt': FieldValue.serverTimestamp(),
                });

                tx.update(postRef, {
                  'likesCount': currentLikes + 1,
                });
              });
            },
            child: Stack(
              alignment: Alignment.center,
              children: [
                Image.network(
                  widget.data['imageUrl'],
                  width: double.infinity,
                  height: 260,
                  fit: BoxFit.cover,
                ),
                if (_showHeart)
                  ScaleTransition(
                    scale: _heartAnimation,
                    child: Icon(
                      Icons.favorite,
                      size: 90,
                      color: Colors.white.withOpacity(0.85),
                    ),
                  ),
              ],
            ),
          ),

        // ================= ACTIONS =================
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              // LIKE BUTTON
              StreamBuilder<DocumentSnapshot>(
                stream: likeRef.snapshots(),
                builder: (_, snap) {
                  final liked = snap.data?.exists ?? false;

                  return IconButton(
                    icon: Icon(
                      liked ? Icons.favorite : Icons.favorite_border,
                      color: liked ? Colors.red : Colors.white,
                    ),
                    onPressed: () async {
                      await FirebaseFirestore.instance
                          .runTransaction((tx) async {
                        final postSnap = await tx.get(postRef);
                        final likeSnap = await tx.get(likeRef);

                        final currentLikes =
                        (postSnap['likesCount'] ?? 0) as int;

                        if (likeSnap.exists) {
                          tx.delete(likeRef);
                          tx.update(postRef, {
                            'likesCount':
                            currentLikes > 0 ? currentLikes - 1 : 0,
                          });
                        } else {
                          tx.set(likeRef, {
                            'createdAt':
                            FieldValue.serverTimestamp(),
                          });
                          tx.update(postRef, {
                            'likesCount': currentLikes + 1,
                          });
                        }
                      });
                    },
                  );
                },
              ),

              // COMMENT BUTTON
              IconButton(
                icon: const Icon(Icons.chat_bubble_outline),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          CommentsScreen(postId: widget.postId),
                    ),
                  );
                },
              ),

              // SHARE (later)
              IconButton(
                icon: const Icon(Icons.send),
                onPressed: () {},
              ),
            ],
          ),
        ),

        // ================= COUNTS =================
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${widget.data['likesCount'] ?? 0} likes',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              StreamBuilder<QuerySnapshot>(
                stream: commentsRef.snapshots(),
                builder: (_, snap) {
                  final count = snap.data?.docs.length ?? 0;
                  if (count == 0) return const SizedBox();
                  return Text(
                    'View all $count comments',
                    style: const TextStyle(color: Colors.white54),
                  );
                },
              ),
            ],
          ),
        ),

        // ================= CAPTION =================
        if ((widget.data['caption'] ?? '').toString().isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: RichText(
              text: TextSpan(
                style: const TextStyle(color: Colors.white),
                children: [
                  TextSpan(
                    text: '${widget.data['userName']} ',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold),
                  ),
                  TextSpan(text: widget.data['caption']),
                ],
              ),
            ),
          ),

        const SizedBox(height: 12),
        const Divider(color: Colors.white12),
      ],
    );
  }
}