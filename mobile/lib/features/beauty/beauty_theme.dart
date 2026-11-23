import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Visual tokens of Beauty & Care (premium violet marketplace). Beauty screens are always light, as in the reference.
abstract final class BeautyColors {
  static const primary = Color(0xFF6C20F5);
  static const primaryDark = Color(0xFF4C13C7);
  static const lavender = Color(0xFFF3EEFF);
  static const background = Color(0xFFFFFFFF);
  static const surface = Color(0xFFF8F7FC);
  static const text = Color(0xFF15121D);
  static const muted = Color(0xFF6B6780);
  static const line = Color(0xFFE7E3F3);
  static const rating = Color(0xFFF2A81D);
  static const success = Color(0xFF1FA463);
  static const error = Color(0xFFD93025);

  /// Call-to-action gradient.
  static const cta = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFFB35CFF), Color(0xFF6514ED)],
  );

  static const hero = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF8A3DFF), Color(0xFF4C13C7)],
  );
}

ThemeData beautyTheme(ThemeData base) {
  final scheme = ColorScheme.fromSeed(
    seedColor: BeautyColors.primary,
    brightness: Brightness.light,
  ).copyWith(
    primary: BeautyColors.primary,
    onPrimary: Colors.white,
    surface: BeautyColors.background,
    onSurface: BeautyColors.text,
  );
  return base.copyWith(
    brightness: Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: BeautyColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: BeautyColors.background,
      foregroundColor: BeautyColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: BeautyColors.background,
      indicatorColor: BeautyColors.lavender,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: states.contains(WidgetState.selected)
              ? BeautyColors.primary
              : BeautyColors.muted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? BeautyColors.primary
              : BeautyColors.muted,
        ),
      ),
    ),
  );
}

/// Beauty routes are pushed above the app navigator, so each one re-applies the light Beauty theme.
class BeautyScope extends StatelessWidget {
  const BeautyScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Theme(data: beautyTheme(Theme.of(context)), child: child);
}

Route<T> beautyRoute<T>(Widget screen) =>
    MaterialPageRoute<T>(builder: (_) => BeautyScope(child: screen));
