import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_mobile/core/localization/kunde_formats.dart';

const _ru = Locale('ru');
const _kk = Locale('kk');
const _en = Locale('en');

String _money(int minor, String currency, Locale locale) =>
    KundeFormats.money(minor, currency, locale);

void main() {
  group('KundeFormats.money', () {
    test('formats integer minor units for ru, kk and en', () {
      expect(_money(123450, 'KZT', _ru), '1 234,50 ₸');
      expect(_money(123450, 'KZT', _kk), '1 234,50 ₸');
      expect(_money(123450, 'KZT', _en), '₸1,234.50');
    });

    test('pads fractions, groups millions, handles zero and negatives', () {
      expect(_money(5, 'KZT', _en), '₸0.05');
      expect(_money(0, 'KZT', _ru), '0,00 ₸');
      expect(_money(100000000, 'KZT', _en), '₸1,000,000.00');
      expect(_money(-250, 'KZT', _ru), '-2,50 ₸');
    });

    test('does not infer currency from language and rejects unknown', () {
      expect(_money(100, 'USD', _ru), '1,00 \$');
      expect(() => _money(100, 'XXX', _ru), throwsArgumentError);
    });
  });
}
