import 'package:flutter/material.dart';

import '../auth/partner_session.dart';
import '../core/strings.dart';

/// Language and theme choice, persisted in the same secure store (it holds no
/// secret, but this avoids another native dependency).
class SettingsController extends ChangeNotifier {
  SettingsController([SecureKeyValue? store])
      : _store = store ?? const FlutterSecureKeyValue();

  final SecureKeyValue _store;
  static const _localeKey = 'kunde.partner.locale.v1';
  static const _themeKey = 'kunde.partner.theme.v1';

  /// null = follow the phone (ru when the phone language is unsupported).
  Locale? _locale;
  ThemeMode _theme = ThemeMode.light;

  Locale? get locale => _locale;
  ThemeMode get themeMode => _theme;

  Future<void> load() async {
    try {
      final l = await _store.read(_localeKey);
      if (l != null && S.supported.any((s) => s.languageCode == l)) {
        _locale = Locale(l);
      }
      final t = await _store.read(_themeKey);
      _theme = switch (t) {
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => ThemeMode.light,
      };
    } on Object {
      // Unreadable preferences fall back to defaults.
    }
    notifyListeners();
  }

  Future<void> setLocale(Locale? value) async {
    _locale = value;
    notifyListeners();
    try {
      if (value == null) {
        await _store.delete(_localeKey);
      } else {
        await _store.write(_localeKey, value.languageCode);
      }
    } on Object {
      // Preference is best effort.
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _theme = mode;
    notifyListeners();
    try {
      await _store.write(
          _themeKey,
          switch (mode) {
            ThemeMode.light => 'light',
            ThemeMode.dark => 'dark',
            ThemeMode.system => 'system',
          });
    } on Object {
      // Preference is best effort.
    }
  }
}
