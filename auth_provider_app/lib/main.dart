import 'package:flutter/material.dart';

import 'splash_page.dart';

void main() {
  runApp(const AuthProviderApp());
}

class AuthProviderApp extends StatelessWidget {
  const AuthProviderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Auth Provider',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const SplashPage(),
    );
  }
}
