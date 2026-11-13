import 'dart:ui' show Locale;

/// Locale-aware formatting for values the PRD (§18) requires to be stored as
/// integers plus an ISO code, plus CLDR plural categories and numeric
/// date/time. Pure Dart: no clock, no device locale lookup, no time-zone
/// conversion and no currency inferred from language.
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

  /// CLDR cardinal plural category for a whole [count] (absolute value used).
  /// ru: one/few/many; kk and en: one/other. Other languages are rejected so a
  /// wrong form is never shown. Approved wording per category is TASK-049.
  static PluralCategory plural(int count, Locale locale) {
    final n = count < 0 ? -count : count;
    switch (locale.languageCode) {
      case 'ru':
        final mod10 = n % 10;
        final mod100 = n % 100;
        if (mod10 == 1 && mod100 != 11) return PluralCategory.one;
        if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
          return PluralCategory.few;
        }
        return PluralCategory.many;
      case 'kk':
      case 'en':
        return n == 1 ? PluralCategory.one : PluralCategory.other;
      default:
        throw ArgumentError.value(locale, 'locale', 'unsupported locale');
    }
  }

  /// Numeric date, already in the caller's intended time zone (no conversion
  /// here). ru/kk: `13.11.2026`. en: `13/11/2026` (day first, as in the
  /// Kazakhstan market; unapproved assumption, see TASK-049).
  static String date(DateTime value, Locale locale) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year.toString().padLeft(4, '0');
    return switch (locale.languageCode) {
      'ru' || 'kk' => '$day.$month.$year',
      'en' => '$day/$month/$year',
      _ => throw ArgumentError.value(locale, 'locale', 'unsupported locale'),
    };
  }

  /// 24-hour time `14:05` for all supported languages (assumption).
  static String time(DateTime value, Locale locale) {
    if (!const {'ru', 'kk', 'en'}.contains(locale.languageCode)) {
      throw ArgumentError.value(locale, 'locale', 'unsupported locale');
    }
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
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

/// CLDR cardinal plural categories used by supported languages.
enum PluralCategory { one, few, many, other }
