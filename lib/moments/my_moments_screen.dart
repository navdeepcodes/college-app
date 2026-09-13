import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:video_player/video_player.dart';

class MyMomentsScreen extends StatelessWidget {
  const MyMomentsScreen({super.key});

  bool _isVideo(String url) => url.endsWith('.mp4');

  Future<void> _deleteMoment(BuildContext context, String id) async {
    await FirebaseFirestore.instance.collection('moments').doc(id).delete();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Moment deleted'),
          backgroundColor: Colors.black87,
        ),
      );
    }
  }

  void _confirmDelete(BuildContext context, String id) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Delete moment?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
            ),
            onPressed: () {
              Navigator.pop(context);
              _deleteMoment(context, id);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text('Not logged in', style: TextStyle(color: Colors.white54)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('My moments'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('moments')
            .where('userId', isEqualTo: user.uid)
            .orderBy('createdAt', descending: true)
            .limit(200)
            .snapshots(),
        builder: (_, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text(
                'Failed to load your moments',
                style: TextStyle(color: Colors.white70),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(
              child: Text(
                'You haven’t posted any moments',
                style: TextStyle(color: Colors.white54),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final data = docs[i].data() as Map<String, dynamic>;
              final mediaUrl = data['mediaUrl'] as String?;
              final reactions =
              Map<String, dynamic>.from(data['reactions'] ?? {});
              final reports = data['reportsCount'] ?? 0;

              return Container(
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: Colors.white.withAlpha(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // MEDIA
                    if (mediaUrl != null)
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(18),
                        ),
                        child: _isVideo(mediaUrl)
                            ? _MyMomentVideo(url: mediaUrl)
                            : Image.network(
                          mediaUrl,
                          height: 220,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),

                    // INFO BAR
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          _reactionStat('🔥', reactions['fire'] ?? 0),
                          const SizedBox(width: 12),
                          _reactionStat('❤️', reactions['heart'] ?? 0),
                          const SizedBox(width: 12),
                          _reactionStat('😂', reactions['laugh'] ?? 0),
                          const Spacer(),

                          if (reports > 0)
                            Text(
                              '⚠ $reports report${reports > 1 ? 's' : ''}',
                              style: const TextStyle(
                                color: Colors.orangeAccent,
                                fontSize: 12,
                              ),
                            ),

                          const SizedBox(width: 10),

                          GestureDetector(
                            onTap: () =>
                                _confirmDelete(context, docs[i].id),
                            child: const Icon(
                              Icons.delete,
                              color: Colors.redAccent,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _reactionStat(String emoji, int count) {
    return Row(
      children: [
        Text(emoji),
        const SizedBox(width: 4),
        Text(
          '$count',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }
}

//
// ================= VIDEO PLAYER =================
//

class _MyMomentVideo extends StatefulWidget {
  final String url;
  const _MyMomentVideo({required this.url});

  @override
  State<_MyMomentVideo> createState() => _MyMomentVideoState();
}

class _MyMomentVideoState extends State<_MyMomentVideo> {
  late final VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        _controller
          ..setLooping(true)
          ..play();
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) {
      return const SizedBox(
        height: 220,
        child: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    return SizedBox(
      height: 220,
      width: double.infinity,
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _controller.value.size.width,
          height: _controller.value.size.height,
          child: VideoPlayer(_controller),
        ),
      ),
    );
  }
}