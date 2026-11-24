import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_localization/kunde_localizations.dart';
import 'package:kunde_admin/features/food_admin/food_admin_screen.dart';
import 'package:kunde_auth/auth_repository.dart';

/// Answers like `/api/v1/admin/groceries`; an empty database yields zeros and empty lists.
class _AdminSession implements AuthRepository {
  _AdminSession({this.empty = false, this.fail = false});

  final bool empty;
  bool fail;
  final calls = <String>[];
  final bodies = <Map<String, dynamic>?>[];

  @override
  Future<dynamic> authorizedJson(String method, String path,
      {Map<String, dynamic>? body,
      Set<int> expected = const {200},
      Map<String, String>? headers}) async {
    calls.add('$method $path');
    bodies.add(body);
    if (fail) throw IdentityApiError(403, 'ADMIN_GRANT_REQUIRED');
    if (path.startsWith('admin/groceries/summary')) {
      return {
        'stores': empty ? 0 : 5,
        'openStores': empty ? 0 : 4,
        'blockedStores': 0,
        'orders': empty ? 0 : 21,
        'deliveredOrders': empty ? 0 : 17,
        'cancelledOrders': 0,
        'activeOrders': 0,
        'revenueMinor': empty ? 0 : 6123000,
        'averageCheckMinor': empty ? 0 : 360000,
        'deliveryOrders': empty ? 0 : 14,
        'pickupOrders': empty ? 0 : 7,
        'refundedMinor': 0,
        'changedOrders': empty ? 0 : 3,
        'problemOrders': 0,
        'openComplaints': 0,
        'lowStockProducts': empty ? 0 : 6,
        'outOfStockProducts': empty ? 0 : 2,
        'uncategorizedProducts': 0,
        'openCourierTasks': empty ? 0 : 1,
        'activeCourierTasks': 0,
        'deliveredCourierTasks': 0,
        'perDay': [
          for (var i = 0; i < 7; i++)
            {'day': '2026-11-1$i', 'orders': empty ? 0 : i, 'revenueMinor': 0}
        ],
        'statuses': empty
            ? []
            : [
                {'status': 'DELIVERED', 'count': 17}
              ],
        'categories': empty
            ? []
            : [
                {'category': 'dairy', 'itemsSold': 40, 'revenueMinor': 2400000},
                {
                  'category': 'fruit_veg',
                  'itemsSold': 30,
                  'revenueMinor': 1200000
                },
              ],
      };
    }
    switch ((method, path)) {
      case ('GET', 'admin/groceries/orders'):
        return [
          {
            'id': 'o-1',
            'store': 'Фреш Маркет',
            'status': 'DELIVERED',
            'fulfillmentType': 'DELIVERY',
            'paymentMethod': 'TEST_CARD',
            'paymentStatus': 'TEST_PAID',
            'totalMinor': 337000,
            'refundedMinor': 0,
            'hasChanges': true,
            'customerRef': 'abcd1234',
            'placedAt': '2026-11-20T10:15:00+05:00',
          }
        ];
      case ('POST', 'admin/groceries/orders/o-1/refund'):
        return {'id': 'o-1', 'paymentStatus': 'REFUNDED'};
      case ('GET', 'admin/groceries/stores'):
        return [
          {
            'id': 's-1',
            'name': 'Фреш Маркет',
            'partner': null,
            'open': true,
            'moderationStatus': 'ACTIVE',
            'ratingAvg': null,
            'ratingCount': 0,
            'orders': 21,
            'products': 30,
            'synthetic': true,
          }
        ];
      case ('POST', 'admin/groceries/stores/s-1/moderation'):
        return [];
      case ('GET', 'admin/groceries/catalog/problems'):
        return [
          {
            'id': 'd-1',
            'name': 'Сыр Российский 200 г',
            'store': 'Фреш Маркет',
            'category': 'dairy',
            'unit': 'PIECE',
            'stockQty': 3,
            'available': true,
            'problem': 'LOW_STOCK',
          }
        ];
      case ('GET', 'admin/groceries/promotions'):
        return [
          {
            'id': 'p-1',
            'code': 'FRESH10',
            'title': 'Скидка 10%',
            'kind': 'PERCENT',
            'value': 10,
            'status': 'ACTIVE',
            'redeemed': 1,
            'restaurantName': 'Фреш Маркет',
          }
        ];
      case ('GET', 'admin/groceries/complaints'):
        return [
          {
            'id': 'c-1',
            'reviewId': 'v-1',
            'store': 'Фреш Маркет',
            'reviewComment': 'Привезли не то',
            'reason': 'Оскорбление',
            'status': 'OPEN',
            'createdAt': '2026-11-20T10:15:00+05:00',
          }
        ];
      case ('POST', 'admin/groceries/complaints/c-1/resolve'):
        return [];
      case ('GET', 'admin/groceries/reviews'):
        return [];
      case ('GET', 'admin/groceries/audit'):
        return [
          {
            'id': 1,
            'actorType': 'ADMIN',
            'action': 'STORE_BLOCK',
            'target': 's-1',
            'detail': 'Проверка',
            'at': '2026-11-20T10:15:00+05:00'
          }
        ];
    }
    throw StateError('Unexpected API call $method $path');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(AuthRepository auth, {String locale = 'ru'}) => MaterialApp(
      locale: Locale(locale),
      supportedLocales: KundeLocalizations.supportedLocales,
      localizationsDelegates: KundeLocalizations.localizationsDelegates,
      home: GroceriesAdminScreen(auth: auth),
    );

void _tall(WidgetTester t, {double width = 900}) {
  t.view.physicalSize = Size(width, 2600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

void main() {
  testWidgets(
      'overview shows KPIs, categories and stock numbers from the server',
      (tester) async {
    _tall(tester);
    final session = _AdminSession();
    await tester.pumpWidget(_app(session));
    await tester.pumpAndSettle();
    expect(find.text('Продукты: центр управления'), findsOneWidget);
    expect(find.text('4 / 5'), findsOneWidget);
    expect(find.text('21'), findsOneWidget);
    expect(find.byKey(const Key('kpi-low-stock')), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    expect(find.text('Молочные продукты'), findsOneWidget);
    expect(find.text('Овощи и фрукты'), findsOneWidget);
    expect(find.byKey(const Key('groceries-admin-empty')), findsNothing);
    expect(session.calls.every((c) => c.contains('admin/groceries')), isTrue,
        reason: 'the screen never calls the Food center');
  });

  testWidgets(
      'an empty database shows zeros, an empty state and no sample figures',
      (tester) async {
    _tall(tester);
    await tester.pumpWidget(_app(_AdminSession(empty: true)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('groceries-admin-empty')), findsOneWidget);
    expect(
        find.byKey(const Key('groceries-admin-no-categories')), findsOneWidget);
    expect(find.text('0 / 0'), findsOneWidget);
    expect(find.textContaining('612 680'), findsNothing);
    expect(find.textContaining('326'), findsNothing);
  });

  testWidgets(
      'a missing grant is a visible failure with retry, not an empty dashboard',
      (tester) async {
    _tall(tester);
    final session = _AdminSession(fail: true);
    await tester.pumpWidget(_app(session));
    await tester.pumpAndSettle();
    expect(find.text('Не удалось загрузить данные'), findsOneWidget);
    session.fail = false;
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();
    expect(find.text('4 / 5'), findsOneWidget);
  });

  testWidgets('orders list has no personal data and the refund needs a reason',
      (tester) async {
    _tall(tester);
    final session = _AdminSession();
    await tester.pumpWidget(_app(session));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, 'Заказы'));
    await tester.pumpAndSettle();
    expect(find.textContaining('abcd1234'), findsOneWidget);
    expect(find.textContaining('замены'), findsOneWidget);
    await tester.tap(find.byKey(const Key('groceries-admin-refund')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('food-admin-reason')), 'x');
    await tester.tap(find.text('Подтвердить'));
    await tester.pumpAndSettle();
    expect(session.calls,
        isNot(contains('POST admin/groceries/orders/o-1/refund')));
    await tester.tap(find.byKey(const Key('groceries-admin-refund')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('food-admin-reason')), 'Тестовый возврат');
    await tester.tap(find.text('Подтвердить'));
    await tester.pumpAndSettle();
    final index =
        session.calls.indexOf('POST admin/groceries/orders/o-1/refund');
    expect(index, greaterThan(-1));
    expect(session.bodies[index], {'reason': 'Тестовый возврат'});
  });

  testWidgets(
      'stores, catalog problems, promotions, complaints and audit come from the server',
      (tester) async {
    _tall(tester);
    final session = _AdminSession();
    await tester.pumpWidget(_app(session));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, 'Магазины'));
    await tester.pumpAndSettle();
    expect(find.textContaining('товаров: 30'), findsOneWidget);
    await tester.tap(find.text('Блок'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('food-admin-reason')), 'Проверка качества');
    await tester.tap(find.text('Подтвердить'));
    await tester.pumpAndSettle();
    final i =
        session.calls.indexOf('POST admin/groceries/stores/s-1/moderation');
    expect(session.bodies[i],
        {'decision': 'BLOCK', 'reason': 'Проверка качества'});

    await tester.tap(find.widgetWithText(Tab, 'Каталог и склад'));
    await tester.pumpAndSettle();
    expect(find.text('Сыр Российский 200 г'), findsOneWidget);
    expect(find.text('Мало на складе'), findsWidgets);
    await tester.tap(find.widgetWithText(Tab, 'Акции'));
    await tester.pumpAndSettle();
    expect(find.textContaining('FRESH10'), findsOneWidget);
    await tester.tap(find.widgetWithText(Tab, 'Жалобы'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('groceries-admin-resolve')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('food-admin-reason')), 'Проверено');
    await tester.tap(find.text('Подтвердить'));
    await tester.pumpAndSettle();
    expect(
        session.calls, contains('POST admin/groceries/complaints/c-1/resolve'));
    await tester.tap(find.widgetWithText(Tab, 'Журнал'));
    await tester.pumpAndSettle();
    expect(find.textContaining('STORE_BLOCK'), findsOneWidget);
  });

  for (final width in [320.0, 360.0]) {
    for (final locale in ['ru', 'kk', 'en']) {
      testWidgets('overview fits $width dp at 200% text in $locale',
          (tester) async {
        tester.view.physicalSize = Size(width, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
            locale: Locale(locale),
            supportedLocales: KundeLocalizations.supportedLocales,
            localizationsDelegates: KundeLocalizations.localizationsDelegates,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!),
            home: GroceriesAdminScreen(auth: _AdminSession())));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
