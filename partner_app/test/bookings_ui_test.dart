import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_partner/features/bookings/booking_filters.dart';
import 'package:kunde_partner/data/models.dart';

import 'support/fake_backend.dart';
import 'support/pump.dart';

Finder dialogButton(String label) => find.descendant(
    of: find.byType(AlertDialog),
    matching: find.widgetWithText(FilledButton, label));

Future<void> openBookings(WidgetTester tester) async {
  await tester.tap(find.text('Записи').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('pending request offers exactly the actions the server allows',
      (tester) async {
    final h = Harness();
    await pumpReady(tester, h);
    await openBookings(tester);
    expect(find.text('Стрижка'), findsOneWidget);
    expect(find.text('Ждёт ответа'), findsOneWidget);
    expect(find.textContaining('Мастер: Алия'), findsOneWidget);
    expect(find.text('Подтвердить'), findsOneWidget);
    expect(find.text('Отклонить'), findsWidgets);
    expect(find.text('Услуга оказана'), findsNothing);
    expect(find.textContaining(bookingId), findsNothing);
    expect(find.text('PENDING'), findsNothing);
  });

  testWidgets('confirm → request sent once, then moves out of Requests',
      (tester) async {
    final b = FakeBackend();
    final h = Harness(backend: b);
    await pumpReady(tester, h);
    await openBookings(tester);
    b.upcoming = [
      bookingJson(status: 'CONFIRMED', allowedActions: const ['CANCEL'])
    ];
    b.requests = [];
    await tester.tap(find.text('Подтвердить'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Клиент увидит новый статус'), findsOneWidget);
    await tester.tap(dialogButton('Подтвердить'));
    await settle(tester, ms: 80);
    expect(
        b.count(
            'POST partner/partners/$partnerId/booking/bookings/$bookingId/action'),
        1);
    expect(find.text('Запись обновлена'), findsOneWidget);
    expect(find.text('Новых заявок нет'), findsOneWidget);
  });

  testWidgets('reject requires a reason and sends it', (tester) async {
    final b = FakeBackend();
    final h = Harness(backend: b);
    await pumpReady(tester, h);
    await openBookings(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Отклонить'));
    await tester.pumpAndSettle();
    expect(find.text('Отклонить заявку'), findsOneWidget);
    expect(tester.widget<FilledButton>(dialogButton('Подтвердить')).onPressed,
        isNull);
    await tester.enterText(find.byType(TextField), 'Мастер заболел');
    await tester.pump();
    await tester.tap(dialogButton('Подтвердить'));
    await settle(tester, ms: 80);
    final post = b.calls.firstWhere(
        (c) => c.startsWith('POST partner/') && c.contains('/action'));
    expect(post, contains(bookingId));
  });

  testWidgets(
      'upcoming confirmed booking can be cancelled; completed shows no actions',
      (tester) async {
    final b = FakeBackend()
      ..requests = []
      ..upcoming = [
        bookingJson(status: 'CONFIRMED', allowedActions: const ['CANCEL'])
      ]
      ..bookingHistory = [
        bookingJson(
            id: 'bbbbbbbb-0000-0000-0000-000000000009',
            status: 'COMPLETED',
            allowedActions: const [],
            startsAt: DateTime.now().subtract(const Duration(days: 2))),
      ];
    final h = Harness(backend: b);
    await pumpReady(tester, h);
    await openBookings(tester);
    await tester.tap(find.text('Предстоящие'));
    await tester.pumpAndSettle();
    expect(find.text('Отменить запись'), findsOneWidget);
    expect(find.text('Подтверждена'), findsOneWidget);
    await tester.tap(find.text('История'));
    await tester.pumpAndSettle();
    expect(find.text('Завершена'), findsWidgets);
    expect(find.text('Отменить запись'), findsNothing);
  });

  testWidgets('date filter hides bookings outside the chosen day',
      (tester) async {
    final b = FakeBackend()
      ..requests = [
        bookingJson(startsAt: DateTime.now().add(const Duration(days: 3))),
      ];
    final h = Harness(backend: b);
    await pumpReady(tester, h);
    await openBookings(tester);
    expect(find.text('Стрижка'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Сегодня'));
    await tester.pumpAndSettle();
    expect(find.text('Стрижка'), findsNothing);
    expect(find.text('Нет записей по фильтру'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Все'));
    await tester.pumpAndSettle();
    expect(find.text('Стрижка'), findsOneWidget);
  });

  test('filterBookings by date range and status', () {
    final now = DateTime(2026, 11, 17, 12);
    PartnerBooking mk(String id, DateTime at, String status) =>
        PartnerBooking.fromJson(
            bookingJson(id: id, status: status, startsAt: at.toUtc()));
    final list = [
      mk('b1', DateTime(2026, 11, 17, 15), 'CONFIRMED'),
      mk('b2', DateTime(2026, 11, 18, 10), 'CONFIRMED'),
      mk('b3', DateTime(2026, 11, 22, 10), 'COMPLETED'),
      mk('b4', DateTime(2026, 11, 30, 10), 'CANCELLED'),
    ];
    List<String> ids(List<PartnerBooking> l) => l.map((b) => b.id).toList();
    expect(ids(filterBookings(list, now: now)), ['b1', 'b2', 'b3', 'b4']);
    expect(ids(filterBookings(list, date: DateFilter.today, now: now)), ['b1']);
    expect(
        ids(filterBookings(list, date: DateFilter.tomorrow, now: now)), ['b2']);
    expect(ids(filterBookings(list, date: DateFilter.week, now: now)),
        ['b1', 'b2', 'b3']);
    expect(ids(filterBookings(list, status: 'COMPLETED', now: now)), ['b3']);
  });

  testWidgets(
      'booking details show service, time, master and price without ids',
      (tester) async {
    final h = Harness();
    await pumpReady(tester, h);
    await openBookings(tester);
    await tester.tap(find.text('Стрижка'));
    await tester.pumpAndSettle();
    expect(find.text('Услуга'), findsOneWidget);
    expect(find.text('Алия'), findsOneWidget);
    expect(find.text('45 мин'), findsOneWidget);
    expect(find.text('Барбершоп партнёра'), findsOneWidget);
    expect(find.textContaining(bookingId), findsNothing);
  });
}
