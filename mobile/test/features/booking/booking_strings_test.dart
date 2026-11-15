import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_mobile/core/localization/kunde_localizations.dart';
import 'package:kunde_mobile/features/booking/data/booking_api.dart';
import 'package:kunde_mobile/features/booking/presentation/booking_strings.dart';
import 'package:kunde_mobile/features/home/presentation/home_strings.dart';

void main() {
  const locales = ['ru', 'kk', 'en'];

  test('categories, cleaning, statuses and errors exist in RU/KK/EN', () {
    for (final code in locales) {
      final s = KundeLocalizations(Locale(code));
      final texts = <String>[
        s.catBeauty,
        s.catHome,
        s.bkBarbers,
        s.bkCleaning,
        s.bkCleaningType,
        s.bkAddress,
        s.bkArea,
        s.bkEstimate,
        s.bkSubmitRequest,
        s.bkCancelBooking,
        s.bkCancelRequest,
        s.bkHistory,
        s.bkSegmentBookings,
        for (final status in ['CONFIRMED', 'COMPLETED', 'CANCELLED'])
          s.bkStatus(status),
        for (final failure in BookingFailure.values) s.bkError(failure),
      ];
      for (final text in texts) {
        expect(text.trim(), isNotEmpty, reason: code);
      }
    }
  });

  test('Kazakh and English differ from the Russian source text', () {
    const ru = KundeLocalizations(Locale('ru'));
    for (final code in ['kk', 'en']) {
      final s = KundeLocalizations(Locale(code));
      expect(s.bkCleaning, isNot(ru.bkCleaning), reason: code);
      expect(s.bkCancelRequest, isNot(ru.bkCancelRequest), reason: code);
      expect(s.bkStatus('CANCELLED'), isNot(ru.bkStatus('CANCELLED')),
          reason: code);
      expect(s.bkError(BookingFailure.slotTaken),
          isNot(ru.bkError(BookingFailure.slotTaken)),
          reason: code);
    }
    expect(
        const KundeLocalizations(Locale('en'))
            .bkCatalogName('Генеральная уборка'),
        'Deep cleaning');
    expect(const KundeLocalizations(Locale('kk')).bkCatalogName('Неизвестная'),
        'Неизвестная');
  });

  test('demo cleaning types and old barbershop names have translations', () {
    const en = KundeLocalizations(Locale('en'));
    for (final name in [
      'Поддерживающая уборка',
      'Генеральная уборка',
      'Уборка после ремонта',
      'Мужская стрижка'
    ]) {
      expect(en.bkCatalogName(name), isNot(name));
    }
  });
}
