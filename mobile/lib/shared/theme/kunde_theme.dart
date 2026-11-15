import 'package:flutter/material.dart';

abstract final class KundeTheme {
  static const _brand = Color(0xFF00875A);
  static const _canvas = Color(0xFFFFFFFF);
  static const _ink = Color(0xFF142B23);

  static final light = ThemeData(
    useMaterial3: true,
    fontFamily: 'KundeSans',
    colorScheme: ColorScheme.fromSeed(
      seedColor: _brand,
      brightness: Brightness.light,
      surface: Colors.white,
      primary: _brand,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFE1F7EB),
      onPrimaryContainer: const Color(0xFF005436),
      surfaceContainerLow: const Color(0xFFF5F7F6),
      surfaceContainerHighest: const Color(0xFFEDF2EF),
      outlineVariant: const Color(0xFFE4EBE7),
    ),
    scaffoldBackgroundColor: _canvas,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: _ink,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: TextStyle(
          fontFamily: 'KundeSans',
          color: _ink,
          fontSize: 20,
          fontWeight: FontWeight.w800),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 2,
      shadowColor: const Color(0x120F4930),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: Color(0xFFEDF2EF)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: const Color(0xFFE1F7EB),
      height: 76,
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? _brand
                : const Color(0xFF5D6963),
          )),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF5F7F6),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: _brand, width: 2)),
    ),
    searchBarTheme: SearchBarThemeData(
      backgroundColor: const WidgetStatePropertyAll(Color(0xFFF5F7F6)),
      elevation: const WidgetStatePropertyAll(0),
      shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true),
    dividerTheme: const DividerThemeData(color: Color(0xFFEDF2EF), space: 24),
    listTileTheme: const ListTileThemeData(
        iconColor: _brand,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4)),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
