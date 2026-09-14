import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'moment_preview_screen.dart';
import '../auth/services/college_detector.dart';

class MomentCameraScreen extends StatefulWidget {
  const MomentCameraScreen({super.key});

  @override
  State<MomentCameraScreen> createState() => _MomentCameraScreenState();
}

class _MomentCameraScreenState extends State<MomentCameraScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _controller;
  CameraLensDirection _lens = CameraLensDirection.front;

  bool _isRecording = false;
  bool _isReady = false;
  Timer? _timer;

  late final AnimationController _recordAnim;

  @override
  void initState() {
    super.initState();
    _recordAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      lowerBound: 0.85,
      upperBound: 1.1,
    );
    _initCamera();
  }

  Future<void> _initCamera() async {
    setState(() => _isReady = false);

    final cameras = await availableCameras();
    final cam = cameras.firstWhere(
          (c) => c.lensDirection == _lens,
      orElse: () => cameras.first,
    );

    final controller = CameraController(
      cam,
      ResolutionPreset.high,
      enableAudio: true,
    );

    await controller.initialize();
    if (!mounted) return;

    setState(() {
      _controller = controller;
      _isReady = true;
    });
  }

  Future<void> _switchCamera() async {
    if (!_isReady) return;

    HapticFeedback.selectionClick();

    setState(() => _isReady = false);

    _lens = _lens == CameraLensDirection.front
        ? CameraLensDirection.back
        : CameraLensDirection.front;

    await _controller?.dispose();
    _controller = null;

    await _initCamera();
  }

  Future<void> _takePhoto() async {
    if (!_isReady || _isRecording) return;

    HapticFeedback.mediumImpact();
    final file = await _controller!.takePicture();
    _openPreview(file.path, isVideo: false);
  }

  Future<void> _startVideo() async {
    if (!_isReady || _isRecording) return;

    HapticFeedback.heavyImpact();
    await _controller!.startVideoRecording();

    setState(() => _isRecording = true);
    _recordAnim.repeat(reverse: true);

    _timer = Timer(const Duration(seconds: 10), _stopVideo);
  }

  Future<void> _stopVideo() async {
    if (!_isRecording) return;

    _timer?.cancel();
    _recordAnim.stop();

    final file = await _controller!.stopVideoRecording();
    setState(() => _isRecording = false);

    _openPreview(file.path, isVideo: true);
  }

  Future<void> _openPreview(String path, {required bool isVideo}) async {
    final visibility = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => MomentPreviewScreen(
          filePath: path,
          isVideo: isVideo,
        ),
      ),
    );

    if (visibility == null) return;

    await _uploadMoment(
      localPath: path,
      isVideo: isVideo,
      visibility: visibility,
    );

    if (mounted) Navigator.pop(context);
  }

  Future<void> _uploadMoment({
    required String localPath,
    required bool isVideo,
    required String visibility,
  }) async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final rows = await supabase.from('profiles').select().eq('id', user.id).limit(1);
    if (rows.isEmpty) return;
    final data = rows.first;

    final anonId = data['anon_id'];
    final collegeId = canonicalCollegeId(data);
    if (anonId == null || collegeId.isEmpty) return;

    final ext = isVideo ? 'mp4' : 'jpg';
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.$ext';
    final path = '${user.id}/$fileName';

    await supabase.storage.from('moments').upload(path, File(localPath));
    final mediaUrl = supabase.storage.from('moments').getPublicUrl(path);

    await supabase.from('moments').insert({
      'user_id': user.id,
      'anon_id': anonId,
      'college_id': collegeId,
      'media_url': mediaUrl,
      'is_video': isVideo,
      'visibility': visibility,
      'expires_at':
          DateTime.now().add(const Duration(hours: 3)).toIso8601String(),
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    _timer?.cancel();
    _recordAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isReady || _controller == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          CameraPreview(_controller!),

          /// Top controls
          Positioned(
            top: 40,
            left: 16,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          Positioned(
            top: 40,
            right: 16,
            child: IconButton(
              icon: const Icon(Icons.cameraswitch, color: Colors.white),
              onPressed: _switchCamera,
            ),
          ),

          /// Capture button
          Positioned(
            bottom: 48,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _takePhoto,
                onLongPress: _startVideo,
                onLongPressUp: _stopVideo,
                child: ScaleTransition(
                  scale: _recordAnim,
                  child: Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _isRecording
                            ? Colors.redAccent
                            : Colors.white,
                        width: 4,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}