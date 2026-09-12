import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  static SupabaseClient get _supabase => Supabase.instance.client;

  static Future<void> signInWithGoogle() async {
    await _supabase.auth.signInWithOAuth(OAuthProvider.google);
  }

  static Future<void> signInWithEmail(
      String email,
      String password,
      ) async {
    await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  static Future<void> signUpWithEmail(
      String email,
      String password,
      ) async {
    await _supabase.auth.signUp(
      email: email,
      password: password,
    );
  }

  static Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  static User? get currentUser => _supabase.auth.currentUser;
}