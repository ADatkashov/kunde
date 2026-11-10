import 'package:flutter/material.dart';

abstract final class KundeTheme {
  static const _brand = Color(0xFF0B6B5E);
  static const _canvas = Color(0xFFF6F7F4);
  static const _ink = Color(0xFF17221F);

  static final light = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _brand,
      brightness: Brightness.light,
      surface: Colors.white,
    ),
    scaffoldBackgroundColor: _canvas,
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
          fontSize: 30, height: 1.2, fontWeight: FontWeight.w700, color: _ink),
      headlineSmall: TextStyle(
          fontSize: 24, height: 1.25, fontWeight: FontWeight.w700, color: _ink),
      titleLarge: TextStyle(
          fontSize: 20, height: 1.3, fontWeight: FontWeight.w600, color: _ink),
      bodyLarge: TextStyle(fontSize: 17, height: 1.5, color: _ink),
      bodyMedium: TextStyle(fontSize: 16, height: 1.5, color: _ink),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );

  static final dark = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF77D8C2),
      brightness: Brightness.dark,
    ),
  );
}
