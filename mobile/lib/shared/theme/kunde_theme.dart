import 'package:flutter/material.dart';
import 'package:kunde_design/kunde_design.dart';

abstract final class KundeTheme {
  static final light = _build(Brightness.light);
  static final dark = _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = KundePalette.scheme(brightness);
    final background = KundePalette.background(brightness);
    final base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      fontFamily: 'KundeSans',
      scaffoldBackgroundColor: background,
    );
    return base.copyWith(
      textTheme: base.textTheme
          .copyWith(
            headlineLarge: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
            ),
            headlineSmall: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
            titleLarge: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
            bodyLarge: const TextStyle(fontSize: 17, height: 1.4),
            bodyMedium: const TextStyle(fontSize: 15, height: 1.4),
          )
          .apply(
            fontFamily: 'KundeSans',
            bodyColor: scheme.onSurface,
            displayColor: scheme.onSurface,
          ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 2,
        shadowColor: KundePalette.shadow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .5)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(showDragHandle: true),
    );
  }
}
