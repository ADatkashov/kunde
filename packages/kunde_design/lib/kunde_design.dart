import 'package:flutter/material.dart';

abstract final class KundePalette {
  static const brand = Color(0xFF7055F5);
  static const lightBackground = Color(0xFFF8F9FC);
  static const darkBackground = Color(0xFF101426);
  static const lightSurface = Color(0xFFFFFFFF);
  static const darkSurface = Color(0xFF191E33);
  static const gold = Color(0xFFF2C77D);
  static const ink = Color(0xFF172033);
  static const deepViolet = Color(0xFF271D62);
  static const violet = Color(0xFF5136B4);
  static const shadow = Color(0x18101426);

  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [deepViolet, violet],
  );

  static Color background(Brightness brightness) =>
      brightness == Brightness.dark ? darkBackground : lightBackground;

  static ColorScheme scheme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return ColorScheme.fromSeed(
      seedColor: brand,
      brightness: brightness,
    ).copyWith(
      primary: dark ? const Color(0xFFC9BEFF) : brand,
      onPrimary: dark ? deepViolet : Colors.white,
      surface: dark ? darkSurface : lightSurface,
      onSurface: dark ? const Color(0xFFF1F0FC) : ink,
    );
  }
}
