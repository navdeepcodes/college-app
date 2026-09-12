import 'package:firebase_auth/firebase_auth.dart';

Future<void> handleEmailLink(String link) async {
  final auth = FirebaseAuth.instance;

  if (auth.isSignInWithEmailLink(link)) {
    final email = auth.currentUser?.email;

    if (email != null) {
      await auth.signInWithEmailLink(
        email: email,
        emailLink: link,
      );
    }
  }
}