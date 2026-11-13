import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_mobile/core/localization/kunde_formats.dart';

void main() {
  group('KundeFormats.money', () {
    test('formats integer minor units for ru, kk and en', () {
      expect(KundeFormats.money(123450, 'KZT', const Locale('ru')),
          '1 234,50 ₸');
      expect(KundeFormats.money(123450, 'KZT', const Locale('kk')),
          '1 234,50 ₸');
      expect(KundeFormats.money(123450, 'KZT', const Locale('en')),
          '₸1,234.50');
    });

    test('pads fractions, groups millions and handles zero and negatives', () {
      expect(KundeFormats.money(5, 'KZT', const Locale('en')), '₸0.05');
      expect(KundeFormats.money(0, 'KZT', const Locale('ru')), '0,00 ₸');
      expect(KundeFormats.money(100000000, 'KZT', const Locale('en')),
          '₸1,000,000.00');
      expect(KundeFormats.money(-250, 'KZT', const Locale('ru')),
          '-2,50 ₸');
    });

    test('does not infer currency from language and rejects unknown codes', () {
      expect(KundeFormats.money(100, 'USD', const Locale('ru')),
          '1,00 \$');
      expect(() => KundeFormats.money(100, 'XXX', const Locale('ru')),
          throwsArgumentError);
    });
  });
}
