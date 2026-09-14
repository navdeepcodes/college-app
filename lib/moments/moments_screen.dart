import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import 'moment_camera_screen.dart';
import 'my_moments_screen.dart';

class MomentsScreen extends StatefulWidget {
  const MomentsScreen({super.key});

  @override
  State<MomentsScreen> createState() => _MomentsScreenState();
}

class _MomentsScreenState extends State<MomentsScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _rotation;
  late final Animation<Offset> _slide;
  late final Animation<double> _opacity;

  int _currentIndex = 0;
  _ReactionBurst? _burst;

  final _colors = const [
    Colors.deepPurple,
    Colors.blueGrey,
    Colors.teal,
    Colors.orangeAccent,
    Colors.pinkAccent,
  ];

  @override
  void initState() {
    super.initState();

    _controller =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 280));

    _rotation = Tween(begin: 0.0, end: -0.06).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    _slide = Tween(begin: Offset.zero, end: const Offset(0, -1.0)).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    _opacity = Tween(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  Future<void> _next(int total) async {
    if (_controller.isAnimating || total <= 1) return;
    await _controller.forward();
    setState(() => _currentIndex = (_currentIndex + 1) % total);
    _controller.reset();
  }

  void _triggerReaction(String emoji, Offset origin) {
    setState(() => _burst = _ReactionBurst(emoji, origin));
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _burst = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,

      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (_) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MyMomentsScreen()),
              );
            },
            itemBuilder: (_) =>
            const [PopupMenuItem(value: 'my', child: Text('My moments'))],
          ),
        ],
      ),

      body: SafeArea(
        child: Stack(
          children: [
            StreamBuilder<List<Map<String, dynamic>>>(
              // RLS (moments_select) already scopes this to the caller's
              // own college and non-hidden rows -- see
              // docs/supabase-security-model.md for why this is a real
              // fix over the Firestore reference (allow read: if true,
              // no collegeId check at all).
              stream: Supabase.instance.client
                  .from('moments')
                  .stream(primaryKey: ['id'])
                  .order('expires_at', ascending: false)
                  .limit(200),
              builder: (_, snap) {
                if (snap.hasError) {
                  return const Center(
                    child: Text(
                      'Failed to load moments',
                      style: TextStyle(color: Colors.white70),
                    ),
                  );
                }

                if (!snap.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  );
                }

                final now = DateTime.now();
                final docs = snap.data!.where((m) {
                  if (m['is_hidden'] == true) return false;
                  final e = DateTime.tryParse(m['expires_at'] ?? '');
                  return e != null && e.isAfter(now);
                }).toList();

                if (docs.isEmpty) {
                  return const Center(
                    child: Text('No moments yet',
                        style: TextStyle(color: Colors.white54)),
                  );
                }

                final data = docs[_currentIndex % docs.length];

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragEnd: (d) {
                    if (d.primaryVelocity != null &&
                        d.primaryVelocity! < -250) {
                      _next(docs.length);
                    }
                  },
                  child: Center(
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (_, __) => Opacity(
                        opacity: _opacity.value,
                        child: Transform.translate(
                          offset: _slide.value *
                              MediaQuery.of(context).size.height,
                          child: Transform.rotate(
                            angle: _rotation.value,
                            child: _MomentCard(
                              docId: data['id'] as String,
                              data: data,
                              color:
                              _colors[_currentIndex % _colors.length],
                              onReact: _triggerReaction,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),

            if (_burst != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: _ReactionBurstView(burst: _burst!),
                ),
              ),

            Positioned(
              bottom: 36,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const MomentCameraScreen(),
                      ),
                    );
                  },
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white54, width: 2),
                    ),
                    child: const Icon(Icons.add,
                        color: Colors.white, size: 32),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

//
// ================= MOMENT CARD =================
//

class _MomentCard extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  final Color color;
  final void Function(String emoji, Offset origin) onReact;

  const _MomentCard({
    required this.docId,
    required this.data,
    required this.color,
    required this.onReact,
  });

  bool get isVideo =>
      (data['media_url'] as String?)?.toLowerCase().endsWith('.mp4') ?? false;

  Future<void> _report(BuildContext context) async {
    try {
      // Atomic increment + auto-hide-at-3, and — unlike the Firestore
      // version — this actually succeeds for a non-owner reporting
      // someone else's moment: report_moment() and the
      // enforce_moments_update_columns trigger it runs through were
      // built specifically to fix the "report always fails" bug the
      // owner-only Firestore rule had (see
      // docs/supabase-security-model.md). Still unreachable in the
      // live product while Moments stays disabled.
      await Supabase.instance.client
          .rpc('report_moment', params: {'p_moment_id': docId});

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reported. Thanks for keeping Moments safe.'),
            backgroundColor: Colors.black87,
          ),
        );
      }
    } catch (e) {
      debugPrint('Report failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Report failed. Please try again later.'),
            backgroundColor: Colors.black87,
          ),
        );
      }
    }
  }

  void _confirmReport(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.black,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Report moment?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'Repeated reports will remove this moment.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style:
            ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(context);
              _report(context);
            },
            child: const Text('Report'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final anonId = data['anon_id'] ?? 'ANON';
    final mediaUrl = data['media_url'];
    final reactions = Map<String, dynamic>.from(data['reactions'] ?? {});

    return Container(
      width: MediaQuery.of(context).size.width * .88,
      height: MediaQuery.of(context).size.height * .72,
      clipBehavior: Clip.antiAlias,
      decoration:
      BoxDecoration(color: color, borderRadius: BorderRadius.circular(28)),
      child: Stack(
        children: [
          Positioned.fill(
            child: isVideo
                ? _MomentVideo(url: mediaUrl)
                : Image.network(mediaUrl, fit: BoxFit.cover),
          ),

          Positioned(
            top: 16,
            left: 16,
            child: Text(anonId,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),

          Positioned(
            top: 12,
            right: 12,
            child: GestureDetector(
              onTap: () => _confirmReport(context),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(120),
                  shape: BoxShape.circle,
                ),
                child:
                const Icon(Icons.flag, color: Colors.white70, size: 18),
              ),
            ),
          ),

          Positioned(
            bottom: 20,
            right: 16,
            child: Column(
              children: [
                _reaction(context, '🔥', reactions['fire'] ?? 0),
                const SizedBox(height: 14),
                _reaction(context, '❤️', reactions['heart'] ?? 0),
                const SizedBox(height: 14),
                _reaction(context, '😂', reactions['laugh'] ?? 0),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _reaction(BuildContext ctx, String e, int c) {
    return GestureDetector(
      onTapDown: (d) => onReact(e, d.globalPosition),
      child: Column(
        children: [
          Text(e, style: const TextStyle(fontSize: 28)),
          Text('$c',
              style:
              const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }
}

//
// ================= VIDEO =================
//

class _MomentVideo extends StatefulWidget {
  final String url;
  const _MomentVideo({required this.url});

  @override
  State<_MomentVideo> createState() => _MomentVideoState();
}

class _MomentVideoState extends State<_MomentVideo> {
  late final VideoPlayerController _v;

  @override
  void initState() {
    super.initState();
    _v = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        _v..setLooping(true)..play();
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    _v.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_v.value.isInitialized) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white));
    }
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: _v.value.size.width,
        height: _v.value.size.height,
        child: VideoPlayer(_v),
      ),
    );
  }
}

//
// ================= REACTION BURST =================
//

class _ReactionBurst {
  final String emoji;
  final Offset origin;
  _ReactionBurst(this.emoji, this.origin);
}

class _ReactionBurstView extends StatelessWidget {
  final _ReactionBurst burst;
  const _ReactionBurstView({required this.burst});

  @override
  Widget build(BuildContext context) {
    final rnd = math.Random();

    return Stack(
      children: List.generate(12, (_) {
        final angle = rnd.nextDouble() * math.pi * 2;
        final distance = 120 + rnd.nextInt(60);

        return Positioned(
          left: burst.origin.dx,
          top: burst.origin.dy,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
            builder: (_, t, __) => Transform.translate(
              offset: Offset(
                math.cos(angle) * distance * t,
                math.sin(angle) * distance * t,
              ),
              child: Transform.scale(
                scale: 1 - t * 0.4,
                child: Opacity(
                  opacity: 1 - t,
                  child: Text(burst.emoji,
                      style: const TextStyle(fontSize: 30)),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}