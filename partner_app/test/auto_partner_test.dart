import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_partner/data/models.dart';

import 'support/fake_backend.dart';
import 'support/pump.dart';

Finder dialogButton(String label) => find.descendant(
    of: find.byType(AlertDialog),
    matching: find.widgetWithText(FilledButton, label));

FakeBackend autoBackend({List<String> actions = const ['CHECK_IN', 'CANCEL']}) {
  return FakeBackend()
    ..requests = []
    ..upcoming = [
      bookingJson(status: 'CONFIRMED', allowedActions: actions, extra: {
        'category': 'AUTO',
        'vehicle': 'Toyota Camry 2018 123ABC02',
        'priceKind': 'FROM',
      })
    ]
    ..venues = [
      {
        'id': 'venue-1',
        'name': 'Тестовое СТО',
        'category': 'AUTO',
        'open': true
      },
    ]
    ..services = [
      {
        'id': 'svc-1',
        'name': 'Замена масла',
        'durationMinutes': 45,
        'priceMinor': 1200000,
        'available': true,
        'priceKind': 'FROM',
        'autoCategory': 'OIL_CHANGE',
        'conditions': ''
      },
    ];
}

void main() {
  test('booking model reads the Auto fields', () {
    final b = PartnerBooking.fromJson(bookingJson(extra: {
      'vehicle': 'Kia Rio 2012',
      'priceKind': 'DIAGNOSTIC',
      'finalPriceMinor': 900000,
      'priceApproval': 'PENDING',
    }));
    expect(b.vehicle, 'Kia Rio 2012');
    expect(b.priceKind, 'DIAGNOSTIC');
    expect(b.finalPriceMinor, 900000);
    expect(b.priceApproval, 'PENDING');
    expect(PartnerBooking.fromJson(bookingJson()).vehicle, isNull);
  });

  testWidgets('upcoming car booking shows the car and the check-in action',
      (tester) async {
    final b = autoBackend();
    await pumpReady(tester, Harness(backend: b));
    await tester.tap(find.text('Записи').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Предстоящие'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Toyota Camry 2018'), findsOneWidget);
    expect(find.text('Принять автомобиль'), findsOneWidget);
    await tester.tap(find.text('Принять автомобиль'));
    await tester.pumpAndSettle();
    expect(find.text('Принять автомобиль клиента?'), findsOneWidget);
    await tester.tap(dialogButton('Подтвердить'));
    await settle(tester, ms: 80);
    expect(b.lastBookingAction?['action'], 'CHECK_IN');
  });

  testWidgets('proposing a final price sends tiyn and validates the amount',
      (tester) async {
    final b = autoBackend(actions: const ['PROPOSE_PRICE', 'COMPLETE']);
    await pumpReady(tester, Harness(backend: b));
    await tester.tap(find.text('Записи').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Предстоящие'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Предложить итоговую цену'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(dialogButton('Подтвердить')).onPressed,
        isNull);
    await tester.enterText(find.byType(TextField), '99999999');
    await tester.pump();
    expect(find.textContaining('от 0 до 1 000 000'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '14000');
    await tester.pump();
    await tester.tap(dialogButton('Подтвердить'));
    await settle(tester, ms: 80);
    expect(b.lastBookingAction?['action'], 'PROPOSE_PRICE');
    expect(b.lastBookingAction?['finalPriceMinor'], 1400000);
  });

  testWidgets(
      'time off page lists, adds validation-free removal and empty state',
      (tester) async {
    final b = autoBackend()
      ..timeOff = [
        {
          'id': 'off-1',
          'masterId': null,
          'startsAt': DateTime.now()
              .add(const Duration(days: 2))
              .toUtc()
              .toIso8601String(),
          'endsAt': DateTime.now()
              .add(const Duration(days: 2, hours: 3))
              .toUtc()
              .toIso8601String(),
          'reason': 'Ремонт подъёмника'
        }
      ];
    await pumpReady(tester, Harness(backend: b), tab: 'Заведение');
    await tester.tap(find.text('Тестовое СТО'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Недоступные периоды'), 300);
    await tester.tap(find.text('Недоступные периоды'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ремонт подъёмника'), findsOneWidget);
    await tester.tap(find.byTooltip('Удалить период'));
    await settle(tester, ms: 80);
    expect(
        b.count(
            'DELETE partner/partners/$partnerId/booking/venues/venue-1/time-off/off-1'),
        1);
    expect(find.text('Недоступных периодов нет'), findsOneWidget);
  });

  testWidgets(
      'service editor sends tiyn, minutes and price kind; rejects bad input',
      (tester) async {
    final b = autoBackend();
    await pumpReady(tester, Harness(backend: b), tab: 'Заведение');
    await tester.tap(find.text('Тестовое СТО'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Изменить услугу').first);
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(1), '7000');
    await tester.enterText(fields.at(2), '50');
    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await tester.pumpAndSettle();
    expect(find.text('15–240 минут, шаг 15'), findsOneWidget);
    expect(b.count('PUT '), 0);
    await tester.enterText(fields.at(2), '60');
    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await settle(tester, ms: 80);
    expect(
        b.count(
            'PUT partner/partners/$partnerId/booking/venues/venue-1/services/svc-1'),
        1);
    expect(find.byWidgetPredicate((w) => w is Text && RegExp(r'7\s000').hasMatch(w.data ?? '')), findsOneWidget);
    expect(find.textContaining('60 мин'), findsOneWidget);
  });

  testWidgets('owner can add a service and a post to a car venue',
      (tester) async {
    final b = autoBackend();
    await pumpReady(tester, Harness(backend: b), tab: 'Заведение');
    await tester.tap(find.text('Тестовое СТО'));
    await tester.pumpAndSettle();
    expect(find.text('Добавить услугу'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Добавить пост'), 300);
    expect(find.text('Добавить пост'), findsOneWidget);
  });
}
