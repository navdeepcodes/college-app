import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class SafeVideoPlayer extends StatefulWidget {
  final String url;
  const SafeVideoPlayer({super.key, required this.url});

  @override
  State<SafeVideoPlayer> createState() => _SafeVideoPlayerState();
}

class _SafeVideoPlayerState extends State<SafeVideoPlayer> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await _controller!
          .initialize()
          .timeout(const Duration(seconds: 5));

      _controller!
        ..setLooping(true)
        ..play();

      if (mounted) setState(() {});
    } catch (_) {
      _failed = true;
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const Center(
        child: Icon(Icons.play_circle_outline,
            size: 48, color: Colors.white54),
      );
    }

    if (_controller == null || !_controller!.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: _controller!.value.size.width,
        height: _controller!.value.size.height,
        child: VideoPlayer(_controller!),
      ),
    );
  }
}