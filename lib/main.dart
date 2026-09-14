import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'secrets.dart';
import 'app/auth_gate.dart';
import 'core/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
  runApp(const TrueKinnApp());
}

class TrueKinnApp extends StatelessWidget {
  const TrueKinnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const AuthGate(),
    );
  }
}
