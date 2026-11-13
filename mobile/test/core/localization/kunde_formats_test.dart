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

  group('KundeFormats.plural', () {
    test('ru follows CLDR one/few/many', () {
      PluralCategory ru(int n) => KundeFormats.plural(n, _ru);
      expect([1, 21, 101].map(ru), everyElement(PluralCategory.one));
      expect([2, 3, 4, 22, 24, 102].map(ru), everyElement(PluralCategory.few));
      expect([0, 5, 11, 12, 14, 20, 25, 111, 112].map(ru),
          everyElement(PluralCategory.many));
      expect(ru(-1), PluralCategory.one);
    });

    test('kk and en only distinguish one and other', () {
      for (final locale in [_kk, _en]) {
        expect(KundeFormats.plural(1, locale), PluralCategory.one);
        expect(KundeFormats.plural(0, locale), PluralCategory.other);
        expect(KundeFormats.plural(2, locale), PluralCategory.other);
        expect(KundeFormats.plural(21, locale), PluralCategory.other);
      }
    });

    test('rejects unsupported languages', () {
      expect(() => KundeFormats.plural(1, const Locale('de')),
          throwsArgumentError);
    });
  });

  group('KundeFormats.date and time', () {
    final value = DateTime(2026, 11, 3, 9, 5);

    test('formats numeric date and 24-hour time', () {
      expect(KundeFormats.date(value, _ru), '03.11.2026');
      expect(KundeFormats.date(value, _kk), '03.11.2026');
      expect(KundeFormats.date(value, _en), '03/11/2026');
      for (final locale in [_ru, _kk, _en]) {
        expect(KundeFormats.time(value, locale), '09:05');
      }
    });

    test('does not convert time zones and rejects unknown languages', () {
      final utc = DateTime.utc(2026, 1, 31, 23, 59);
      expect(KundeFormats.date(utc, _ru), '31.01.2026');
      expect(KundeFormats.time(utc, _ru), '23:59');
      expect(() => KundeFormats.date(value, const Locale('de')),
          throwsArgumentError);
      expect(() => KundeFormats.time(value, const Locale('de')),
          throwsArgumentError);
    });
  });
}
