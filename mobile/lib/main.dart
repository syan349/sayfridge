import 'package:flutter/material.dart';

import 'screens/sign_in_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const SayFridgeApp());
}

class SayFridgeApp extends StatelessWidget {
  const SayFridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SayFridge',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const SignInScreen(),
    );
  }
}
