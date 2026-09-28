import 'package:flutter/material.dart';

abstract final class AppColors {
  static const background = Color(0xFFF7FDED);
  static const primary = Color(0xFF91C35E);
  static const primaryDark = Color(0xFF679C35);
  static const primarySoft = Color(0xFFDDF0C6);
  static const userMessage = Color(0xFFC8E5A8);
  static const yellowSoft = Color(0xFFFFE99A);
  static const fieldBorder = Color(0xFFDADADA);
  static const muted = Color(0xFF929292);
  static const text = Color(0xFF111111);
}

abstract final class AppTheme {
  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
      surface: AppColors.background,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: 'Arial',
      textTheme: const TextTheme(
        displaySmall: TextStyle(
          color: AppColors.text,
          fontSize: 44,
          fontWeight: FontWeight.w700,
          height: 1.05,
        ),
        headlineMedium: TextStyle(
          color: AppColors.text,
          fontSize: 28,
          fontWeight: FontWeight.w700,
        ),
        titleLarge: TextStyle(
          color: AppColors.text,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: TextStyle(
          color: AppColors.text,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: TextStyle(color: AppColors.text, fontSize: 16),
        bodyMedium: TextStyle(color: AppColors.text, fontSize: 14),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        hintStyle: const TextStyle(color: Color(0xFFA6A6A6), fontSize: 16),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.fieldBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.fieldBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
            color: AppColors.primaryDark,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
      ),
    );
  }
}
