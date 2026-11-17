import 'package:flutter/material.dart';

/// Design tokens of KUNDE Partner. Widgets read spacing, radii and semantic
/// colors from here instead of hard-coding values.
abstract final class Gap {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

abstract final class Radii {
  static const double card = 16;
  static const double control = 14;
  static const double chip = 10;
}

/// Minimum interactive size (Material / WCAG target size).
const double kMinTap = 48;

/// Deep KUNDE green.
const Color kBrandGreen = Color(0xFF0B6B47);

/// Semantic colors that the Material scheme does not provide.
@immutable
class KundeTones extends ThemeExtension<KundeTones> {
  const KundeTones({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.info,
    required this.infoContainer,
  });

  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color info;
  final Color infoContainer;

  static const light = KundeTones(
    success: Color(0xFF0B6B47),
    onSuccess: Color(0xFFFFFFFF),
    successContainer: Color(0xFFD7F2E3),
    warning: Color(0xFF8A5300),
    onWarning: Color(0xFFFFFFFF),
    warningContainer: Color(0xFFFFE9C2),
    info: Color(0xFF0B5C8A),
    infoContainer: Color(0xFFD8EAF7),
  );

  static const dark = KundeTones(
    success: Color(0xFF7FD8A8),
    onSuccess: Color(0xFF00391F),
    successContainer: Color(0xFF0F4D33),
    warning: Color(0xFFFFC46B),
    onWarning: Color(0xFF442B00),
    warningContainer: Color(0xFF5E3C00),
    info: Color(0xFF9CCBEF),
    infoContainer: Color(0xFF123F5C),
  );

  @override
  KundeTones copyWith() => this;

  @override
  KundeTones lerp(ThemeExtension<KundeTones>? other, double t) =>
      t < 0.5 ? this : (other as KundeTones? ?? this);
}

extension KundeTheme on BuildContext {
  KundeTones get tones =>
      Theme.of(this).extension<KundeTones>() ?? KundeTones.light;
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: kBrandGreen,
    brightness: brightness,
  ).copyWith(
    primary: dark ? const Color(0xFF7FD8A8) : kBrandGreen,
    onPrimary: dark ? const Color(0xFF00391F) : Colors.white,
    error: dark ? const Color(0xFFFFB4AB) : const Color(0xFFB3261E),
  );
  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(Radii.control),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    scaffoldBackgroundColor:
        dark ? const Color(0xFF0F1512) : const Color(0xFFF4F7F5),
    extensions: [dark ? KundeTones.dark : KundeTones.light],
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      foregroundColor: scheme.onSurface,
      titleTextStyle: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: dark ? const Color(0xFF18211C) : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
        side: BorderSide(
          color: dark ? const Color(0xFF2B3A32) : const Color(0xFFE1E8E4),
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(kMinTap, 52),
        shape: shape,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(kMinTap, 52),
        shape: shape,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(kMinTap, kMinTap),
        shape: shape,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      backgroundColor: dark ? const Color(0xFF18211C) : Colors.white,
      indicatorColor: scheme.primaryContainer,
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.chip),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    dividerTheme: const DividerThemeData(space: 1, thickness: 1),
  );
}
