import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_partner/data/models.dart';
import 'package:kunde_partner/features/business/dish_sheet.dart';
import 'package:kunde_partner/features/business/hours_page.dart';

import 'support/fake_backend.dart';
import 'support/pump.dart';

FakeBackend backend({String role = 'OWNER'}) {
  final b = FakeBackend();
  b.partners = [
    {
      'id': partnerId,
      'displayName': 'Демо-партнёр',
      'verificationStatus': 'APPROVED',
      'version': 1,
      'role': role
    },
  ];
  b.operatorRole = role == 'OPERATOR';
  return b;
}

void main() {
  foodSettingsTests();
  test('price parsing: tenge with optional kopeks, bounded', () {
    expect(parsePriceMinor('1500'), 150000);
    expect(parsePriceMinor('1 500'), 150000);
    expect(parsePriceMinor('1500,5'), 150050);
    expect(parsePriceMinor('0'), 0);
    expect(parsePriceMinor('1000000'), 100000000);
    expect(parsePriceMinor('1000001'), isNull);
    expect(parsePriceMinor(''), isNull);
    expect(parsePriceMinor('abc'), isNull);
    expect(parsePriceMinor('-5'), isNull);
    expect(parsePriceMinor('1.234'), isNull);
  });

  test('schedule validation mirrors the backend rules', () {
    WorkingHours h(int day, String from, String to, {String? bf, String? bt}) =>
        WorkingHours(day: day, from: from, to: to, breakFrom: bf, breakTo: bt);
    expect(
        hoursValid([
          h(1, '10:00', '19:00', bf: '13:00', bt: '14:00'),
          h(2, '09:30', '18:00')
        ]),
        isTrue);
    expect(hoursValid([]), isTrue, reason: 'all days off is allowed');
    expect(hoursValid([h(1, '19:00', '10:00')]), isFalse);
    expect(hoursValid([h(1, '10:00', '10:00')]), isFalse);
    expect(
        hoursValid([h(1, '10:00', '19:00'), h(1, '10:00', '12:00')]), isFalse,
        reason: 'duplicate weekday');
    expect(hoursValid([h(8, '10:00', '19:00')]), isFalse);
    expect(
        hoursValid([h(1, '10:00', '19:00', bf: '09:00', bt: '11:00')]), isFalse,
        reason: 'break before start');
    expect(hoursValid([h(1, '10:00', '19:00', bf: '13:00')]), isFalse,
        reason: 'half a break');
    expect(hoursValid([h(1, '10:00', '19:00', bf: '14:00', bt: '13:00')]),
        isFalse);
  });

  testWidgets('owner sees open switches and toggling sends exactly one PATCH',
      (tester) async {
    final b = backend();
    final h = Harness(backend: b);
    await pumpReady(tester, h, tab: 'Заведение');
    expect(find.text('Рестораны'), findsOneWidget);
    expect(find.text('Услуги и записи'), findsOneWidget);
    expect(find.byType(Switch), findsNWidgets(2));
    await tester.tap(find.byType(Switch).first);
    await settle(tester, ms: 80);
    expect(b.count('PATCH partner/partners/$partnerId/food/restaurants/rest-1'),
        1);
    expect(find.text('Закрыто'), findsOneWidget);
  });

  testWidgets('an operator sees the state only: no switches, no edit actions',
      (tester) async {
    final b = backend(role: 'OPERATOR');
    final h = Harness(backend: b);
    await pumpReady(tester, h, tab: 'Заведение');
    expect(find.byType(Switch), findsNothing);
    expect(find.text('Открыто'), findsNWidgets(2));
    await tester.tap(find.text('Кухня партнёра'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.text('Добавить блюдо'), findsNothing);
    expect(find.textContaining('владелец и менеджер'), findsOneWidget);
    // availability stays available to operators
    expect(find.byType(Switch), findsNWidgets(2));
  });

  testWidgets(
      'menu groups dishes by section, availability toggle sends only that field',
      (tester) async {
    final b = backend();
    final h = Harness(backend: b);
    await pumpReady(tester, h, tab: 'Заведение');
    await tester.tap(find.text('Кухня партнёра'));
    await tester.pumpAndSettle();
    expect(find.text('Горячее'), findsOneWidget);
    expect(find.text('Напитки'), findsOneWidget);
    expect(find.textContaining('Лагман'), findsOneWidget);
    expect(find.textContaining('Остаток: 5'), findsOneWidget);
    await tester.tap(find.byType(Switch).first);
    await settle(tester, ms: 80);
    final patch = b.calls
        .where((c) => c.startsWith('PATCH') && c.contains('/dishes/dish-1'));
    expect(patch, hasLength(1));
    expect(find.textContaining('Нет в наличии'), findsOneWidget);
  });

  testWidgets('editing a price validates first and then patches only the price',
      (tester) async {
    final b = backend();
    final h = Harness(backend: b);
    await pumpReady(tester, h, tab: 'Заведение');
    await tester.tap(find.text('Кухня партнёра'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined).first);
    await tester.pumpAndSettle();
    expect(find.text('Изменить блюдо'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextField, 'Цена, ₸'), '5000000');
    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await tester.pump();
    expect(find.text('Цена: от 0 до 1 000 000 ₸'), findsOneWidget);
    expect(b.count('PATCH'), 0,
        reason: 'invalid input never reaches the server');
    await tester.enterText(find.widgetWithText(TextField, 'Цена, ₸'), '1 500');
    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await settle(tester, ms: 80);
    expect(
        b.count(
            'PATCH partner/partners/$partnerId/food/restaurants/rest-1/dishes/dish-1'),
        1);
    expect(b.dishes.first['priceMinor'], 150000);
  });

  testWidgets('adding a dish posts section, name and price', (tester) async {
    final b = backend();
    final h = Harness(backend: b);
    await pumpReady(tester, h, tab: 'Заведение');
    await tester.tap(find.text('Кухня партнёра'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Добавить блюдо'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Название'), 'Манты');
    await tester.enterText(find.widgetWithText(TextField, 'Цена, ₸'), '2200');
    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await settle(tester, ms: 80);
    expect(
        b.count(
            'POST partner/partners/$partnerId/food/restaurants/rest-1/dishes'),
        1);
    expect(b.dishes.last['priceMinor'], 220000);
  });

  testWidgets(
      'product card saves Groceries fields, validates the old price and manages photos',
      (tester) async {
    final b = backend();
    final h = Harness(backend: b);
    await pumpReady(tester, h, tab: 'Заведение');
    // A tall screen keeps the whole long form built, so the fields can be reached without scrolling.
    tester.view.physicalSize = const Size(1080, 5200);
    addTearDown(tester.view.reset);
    await tester.tap(find.text('Кухня партнёра'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined).first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Карточка товара'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Карточка товара ·'), findsOneWidget);

    // The price before a discount must be above the current price: nothing reaches the server otherwise.
    await tester.enterText(find.widgetWithText(TextField, 'Бренд'), 'Жайлау');
    await tester.enterText(find.widgetWithText(TextField, 'Ккал'), '52');
    await tester.enterText(
        find.widgetWithText(
            TextField, 'Цена до скидки, ₸ (пусто — без скидки)'),
        '1');
    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await tester.pump();
    expect(find.text('Цена до скидки должна быть выше текущей цены'),
        findsOneWidget);
    expect(b.count('PATCH'), 0);
    await tester.enterText(
        find.widgetWithText(
            TextField, 'Цена до скидки, ₸ (пусто — без скидки)'),
        '99999');
    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await settle(tester, ms: 80);
    expect(
        b.count(
            'PATCH partner/partners/$partnerId/food/restaurants/rest-1/dishes/dish-1/product'),
        1);
    expect(b.dishes.first['brand'], 'Жайлау');
    expect(b.dishes.first['kcal'], 52);
    expect(b.dishes.first['compareAtPriceMinor'], 9999900);

    // Photos accept only https links.
    await tester.enterText(
        find.widgetWithText(TextField, 'Ссылка на фото (https://…)'),
        'http://x.test/a.jpg');
    await tester.scrollUntilVisible(find.text('Добавить фото'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Добавить фото'));
    await tester.pump();
    expect(find.text('Нужна ссылка https://'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextField, 'Ссылка на фото (https://…)'),
        'https://img.example.test/a.jpg');
    await tester.tap(find.text('Добавить фото'));
    await settle(tester, ms: 80);
    expect((b.dishes.first['photos'] as List), hasLength(1));
    await tester.tap(find.byTooltip('Убрать фото'));
    await settle(tester, ms: 80);
    expect((b.dishes.first['photos'] as List), isEmpty);
  });

  testWidgets('a weighed product is created with unit KG', (tester) async {
    final b = backend();
    final h = Harness(backend: b);
    await pumpReady(tester, h, tab: 'Заведение');
    await tester.tap(find.text('Кухня партнёра'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Добавить блюдо'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Название'), 'Яблоки');
    await tester.tap(find.text('На вес (цена за кг)'));
    await tester.enterText(find.widgetWithText(TextField, 'Цена, ₸'), '590');
    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await settle(tester, ms: 80);
    expect(b.dishes.last['unit'], 'KG');
  });

  testWidgets('a forbidden change is explained and the switch stays unchanged',
      (tester) async {
    final b = backend();
    final h = Harness(backend: b);
    await pumpReady(tester, h, tab: 'Заведение');
    b.overrides['PATCH partner/partners/$partnerId/food/restaurants/rest-1'] =
        (_) => b.error(403, 'PARTNER_ROLE_FORBIDDEN');
    await tester.tap(find.byType(Switch).first);
    await settle(tester, ms: 80);
    expect(find.text('Для этого действия недостаточно прав.'), findsOneWidget);
    expect(find.text('Открыто'), findsWidgets);
  });

  testWidgets(
      'venue page: services, specialists, weekly schedule and slots note',
      (tester) async {
    final b = backend();
    final h = Harness(backend: b);
    await pumpReady(tester, h, tab: 'Заведение');
    await tester.tap(find.text('Барбершоп партнёра'));
    await tester.pumpAndSettle();
    expect(find.text('Стрижка'), findsOneWidget);
    expect(find.textContaining('45 мин'), findsOneWidget);
    expect(find.text('Алия'), findsOneWidget);
    expect(find.text('10:00–19:00 (Перерыв 13:00–14:00)'), findsOneWidget);
    expect(find.text('Выходной'), findsWidgets,
        reason: 'days without hours are days off');
    await tester.scrollUntilVisible(
        find.textContaining('Свободные слоты'), 300);
    expect(find.textContaining('формируются автоматически'), findsOneWidget);
  });

  testWidgets(
      'schedule editor saves the remaining working days; conflict is explained',
      (tester) async {
    final b = backend();
    final h = Harness(backend: b);
    await pumpReady(tester, h, tab: 'Заведение');
    await tester.tap(find.text('Барбершоп партнёра'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Изменить график'));
    await tester.pumpAndSettle();
    // turn Tuesday off
    await tester.tap(find.byType(Switch).at(1));
    await tester.pump();
    b.overrides[
            'PUT partner/partners/$partnerId/booking/venues/venue-1/masters/m1/hours'] =
        (_) => b.error(409, 'SCHEDULE_CONFLICT');
    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await settle(tester, ms: 80);
    expect(find.textContaining('Есть записи клиентов'), findsOneWidget);
    b.overrides.clear();
    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await settle(tester, ms: 80);
    final hours = b.masters.first['hours'] as List;
    expect(hours.map((e) => (e as Map)['day']), [1]);
    expect(find.text('График сохранён'), findsWidgets);
  });

  testWidgets('a restaurant-only partner has no booking section in Business',
      (tester) async {
    final b = backend()..venues = [];
    final h = Harness(backend: b);
    await pumpReady(tester, h, tab: 'Заведение');
    expect(find.text('Услуги и записи'), findsNothing);
    expect(find.text('Рестораны'), findsOneWidget);
  });
}

void foodSettingsTests() {
  testWidgets(
      'owner changes pickup and preparation time, sent as one PATCH each',
      (tester) async {
    final b = backend();
    final h = Harness(backend: b);
    await pumpReady(tester, h, tab: 'Заведение');
    await tester.tap(find.text('Кухня партнёра'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('restaurant-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pickup-switch')));
    await settle(tester, ms: 80);
    expect(
        b.calls.where((c) =>
            c.startsWith('PATCH') && c.contains('food/restaurants/rest-1')),
        hasLength(1));
    expect(
        tester
            .widget<SwitchListTile>(find.byKey(const Key('pickup-switch')))
            .value,
        isFalse);
    await tester.tap(find.byKey(const Key('prep-plus')));
    await settle(tester, ms: 80);
    expect(find.textContaining('25 мин'), findsOneWidget);
  });

  testWidgets('operator has no settings entry', (tester) async {
    final b = backend(role: 'OPERATOR');
    final h = Harness(backend: b);
    await pumpReady(tester, h, tab: 'Заведение');
    await tester.tap(find.text('Кухня партнёра'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('restaurant-settings')), findsNothing);
  });

  testWidgets('owner creates a promotion; the form refuses an empty title',
      (tester) async {
    final b = backend();
    final h = Harness(backend: b);
    await pumpReady(tester, h, tab: 'Заведение');
    await tester.tap(find.text('Кухня партнёра'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('restaurant-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-promotions')));
    await tester.pumpAndSettle();
    expect(find.text('Акций пока нет'), findsOneWidget);
    await tester.tap(find.byKey(const Key('new-promotion')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('promo-submit')));
    await tester.pumpAndSettle();
    expect(b.count('POST partner/partners/$partnerId/food/promotions'), 0);
    await tester.enterText(
        find.byKey(const Key('promo-title')), 'Скидка недели');
    await tester.enterText(find.byKey(const Key('promo-code')), 'week15');
    await tester.enterText(find.byKey(const Key('promo-value')), '15');
    await tester.tap(find.byKey(const Key('promo-submit')));
    await settle(tester, ms: 80);
    expect(b.count('POST partner/partners/$partnerId/food/promotions'), 1);
    expect(find.text('Скидка недели'), findsOneWidget);
    expect(find.textContaining('WEEK15'), findsOneWidget);
    await tester.tap(find.byKey(const Key('promotion-toggle-promo-1')));
    await settle(tester, ms: 80);
    expect(find.textContaining('PAUSED'), findsOneWidget);
  });
}
