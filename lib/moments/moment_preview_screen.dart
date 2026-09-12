import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class MomentPreviewScreen extends StatefulWidget {
  final String filePath;
  final bool isVideo;

  const MomentPreviewScreen({
    super.key,
    required this.filePath,
    required this.isVideo,
  });

  @override
  State<MomentPreviewScreen> createState() =>
      _MomentPreviewScreenState();
}

class _MomentPreviewScreenState extends State<MomentPreviewScreen> {
  VideoPlayerController? _videoController;

  @override
  void initState() {
    super.initState();

    if (widget.isVideo) {
      _videoController = VideoPlayerController.file(
        File(widget.filePath),
      )..initialize().then((_) {
        setState(() {});
        _videoController!.play();
      });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  void _select(String visibility) {
    Navigator.pop(context, visibility);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: widget.isVideo
                ? (_videoController != null &&
                _videoController!.value.isInitialized)
                ? AspectRatio(
              aspectRatio:
              _videoController!.value.aspectRatio,
              child: VideoPlayer(_videoController!),
            )
                : const CircularProgressIndicator()
                : Image.file(
              File(widget.filePath),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            ),
          ),

          // ❌ CLOSE
          Positioned(
            top: 40,
            left: 20,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          // 🔘 OPTIONS
          Positioned(
            bottom: 36,
            left: 20,
            right: 20,
            child: Column(
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.visibility_off),
                  label: const Text('College (Anonymous)'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: () => _select('college'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.people),
                  label: const Text('Friends'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: () => _select('friends'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}