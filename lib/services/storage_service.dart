library storage_service;

import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

class StorageService {
  SupabaseClient get _supabase => Supabase.instance.client;

  // ================= PROFILE IMAGE =================
  Future<String> uploadProfileImage({
    required String userId,
    required File file,
  }) async {
    final path = 'profiles/$userId.jpg';

    await _supabase.storage.from('profile_photos').upload(
      path,
      file,
      fileOptions: const FileOptions(upsert: true),
    );

    return _supabase.storage
        .from('profile_photos')
        .getPublicUrl(path);
  }

  // ================= POST MEDIA =================
  Future<String> uploadPostMedia({
    required String userId,
    required String postId,
    required File file,
  }) async {
    final path = 'posts/$userId/$postId.jpg';

    await _supabase.storage.from('posts').upload(
      path,
      file,
      fileOptions: const FileOptions(upsert: true),
    );

    return path;
  }

  String getPublicPostUrl(String path) {
    return _supabase.storage.from('posts').getPublicUrl(path);
  }

  // ================= MOMENTS =================
  Future<String> uploadMoment({
    required String userId,
    required File file,
  }) async {
    final path =
        'moments/$userId/${DateTime.now().millisecondsSinceEpoch}.jpg';

    await _supabase.storage.from('moments').upload(path, file);
    return _supabase.storage.from('moments').getPublicUrl(path);
  }

  // ================= EVENT MEDIA =================
  Future<String> uploadEventMedia({
    required String eventId,
    required File file,
  }) async {
    final path =
        'events/$eventId/${DateTime.now().millisecondsSinceEpoch}.jpg';

    await _supabase.storage.from('events').upload(path, file);
    return _supabase.storage.from('events').getPublicUrl(path);
  }
}