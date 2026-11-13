import 'dart:ui' show Locale;

/// Locale-aware formatting for values the PRD (§18) requires to be stored as
/// integers plus an ISO code. Pure Dart: no clock, no device locale lookup and
/// no currency inferred from language.
class KundeFormats {
  const KundeFormats._();

  static const _symbols = <String, String>{
    'KZT': '₸',
    'RUB': '₽',
    'USD': r'$',
    'EUR': '€',
  };

  /// Minor-unit exponent per supported ISO 4217 code. Unknown codes are
  /// rejected instead of guessed so a wrong amount is never shown.
  static const _minorDigits = <String, int>{
    'KZT': 2,
    'RUB': 2,
    'USD': 2,
    'EUR': 2,
  };

  /// Formats [minorUnits] (for example tiyn) of [currency] for [locale].
  /// ru/kk: `1 234,50 ₸` (no-break spaces). en: `₸1,234.50`.
  static String money(int minorUnits, String currency, Locale locale) {
    final digits = _minorDigits[currency];
    if (digits == null) {
      throw ArgumentError.value(currency, 'currency', 'unsupported currency');
    }
    final negative = minorUnits < 0;
    final abs = negative ? -minorUnits : minorUnits;
    final divisor = _pow10(digits);
    final whole = abs ~/ divisor;
    final fraction = (abs % divisor).toString().padLeft(digits, '0');
    final english = locale.languageCode == 'en';
    final groupSeparator = english ? ',' : ' ';
    final decimalSeparator = english ? '.' : ',';
    final number =
        '${_group(whole.toString(), groupSeparator)}$decimalSeparator$fraction';
    final symbol = _symbols[currency] ?? currency;
    final sign = negative ? '-' : '';
    return english ? '$sign$symbol$number' : '$sign$number $symbol';
  }

  static int _pow10(int exponent) {
    var result = 1;
    for (var i = 0; i < exponent; i++) {
      result *= 10;
    }
    return result;
  }

  static String _group(String digits, String separator) {
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) {
        buffer.write(separator);
      }
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}
