import 'package:flutter/widgets.dart';

/// Locale-aware money and date text, without extra packages.
String formatMoney(int minor, {String currency = 'KZT'}) {
  final negative = minor < 0;
  final abs = minor.abs();
  final whole = abs ~/ 100;
  final cents = abs % 100;
  final digits = whole.toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(' ');
    buf.write(digits[i]);
  }
  final fraction = cents == 0 ? '' : ',${cents.toString().padLeft(2, '0')}';
  final symbol = currency == 'KZT' ? '₸' : currency;
  return '${negative ? '−' : ''}$buf$fraction $symbol';
}

String two(int v) => v.toString().padLeft(2, '0');

String formatTime(DateTime t) => '${two(t.hour)}:${two(t.minute)}';

const _months = {
  'ru': [
    'янв',
    'фев',
    'мар',
    'апр',
    'мая',
    'июн',
    'июл',
    'авг',
    'сен',
    'окт',
    'ноя',
    'дек'
  ],
  'kk': [
    'қаң',
    'ақп',
    'нау',
    'сәу',
    'мам',
    'мау',
    'шіл',
    'там',
    'қыр',
    'қаз',
    'қар',
    'жел'
  ],
  'en': [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ],
};

String formatDate(DateTime t, Locale locale) {
  final names = _months[locale.languageCode] ?? _months['ru']!;
  return '${t.day} ${names[t.month - 1]}';
}

String formatDateTime(DateTime t, Locale locale) =>
    '${formatDate(t, locale)}, ${formatTime(t)}';

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Whole minutes left until [deadline] (never negative).
int minutesLeft(DateTime deadline, DateTime now) {
  final d = deadline.difference(now);
  if (d.isNegative) return 0;
  return (d.inSeconds / 60).ceil();
}
