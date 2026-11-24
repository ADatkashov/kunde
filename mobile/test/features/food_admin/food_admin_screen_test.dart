import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_localization/kunde_localizations.dart';
import 'package:kunde_mobile/features/food_admin/food_admin_screen.dart';
import 'package:kunde_auth/auth_repository.dart';

/// Answers like `/api/v1/admin/food`; an empty database yields zeros and empty lists.
class _AdminSession implements AuthRepository {
  _AdminSession({this.empty = false});

  final bool empty;
  final calls = <String>[];
  final bodies = <Map<String, dynamic>?>[];

  @override
  Future<dynamic> authorizedJson(String method, String path,
      {Map<String, dynamic>? body,
      Set<int> expected = const {200},
      Map<String, String>? headers}) async {
    calls.add('$method $path');
    bodies.add(body);
    if (path.startsWith('admin/food/summary')) {
      return {
        'restaurants': empty ? 0 : 8,
        'openRestaurants': empty ? 0 : 7,
        'blockedRestaurants': 0,
        'orders': empty ? 0 : 12,
        'deliveredOrders': empty ? 0 : 9,
        'cancelledOrders': 0,
        'activeOrders': 0,
        'revenueMinor': empty ? 0 : 4500000,
        'averageCheckMinor': empty ? 0 : 500000,
        'deliveryOrders': empty ? 0 : 8,
        'pickupOrders': empty ? 0 : 4,
        'refundedMinor': 0,
        'openComplaints': 0,
        'hiddenReviews': 0,
        'problemOrders': 0,
        'perDay': [
          for (var i = 0; i < 7; i++)
            {'day': '2026-11-1$i', 'orders': empty ? 0 : i, 'revenueMinor': 0}
        ],
        'statuses': empty
            ? []
            : [
                {'status': 'DELIVERED', 'count': 9}
              ],
      };
    }
    switch ((method, path)) {
      case ('GET', 'admin/food/orders'):
        return [
          {
            'id': 'o-1',
            'restaurant': 'Пицца Тест',
            'vertical': 'FOOD',
            'status': 'DELIVERED',
            'fulfillmentType': 'PICKUP',
            'paymentMethod': 'TEST_CARD',
            'paymentStatus': 'TEST_PAID',
            'totalMinor': 350000,
            'refundedMinor': 0,
            'customerRef': 'abcd1234',
            'placedAt': '2026-11-20T10:15:00+05:00',
          }
        ];
      case ('POST', 'admin/food/orders/o-1/refund'):
        return {'id': 'o-1', 'paymentStatus': 'REFUNDED'};
      case ('GET', 'admin/food/restaurants'):
        return [
          {
            'id': 'r-1',
            'name': 'Пицца Тест',
            'vertical': 'FOOD',
            'partner': null,
            'open': true,
            'moderationStatus': 'ACTIVE',
            'ratingAvg': 4.5,
            'ratingCount': 2,
            'orders': 3,
            'synthetic': true,
          }
        ];
      case ('POST', 'admin/food/restaurants/r-1/moderation'):
        return [];
      case ('GET', 'admin/food/promotions'):
        return [
          {
            'id': 'p-1',
            'code': 'WELCOME10',
            'title': 'Скидка 10%',
            'kind': 'PERCENT',
            'value': 10,
            'status': 'ACTIVE',
            'redeemed': 1,
            'partnerOwned': false,
          }
        ];
      case ('GET', 'admin/food/reviews'):
        return [];
      case ('GET', 'admin/food/audit'):
        return [];
    }
    throw StateError('Unexpected API call $method $path');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(AuthRepository auth) => MaterialApp(
      locale: const Locale('ru'),
      supportedLocales: KundeLocalizations.supportedLocales,
      localizationsDelegates: KundeLocalizations.localizationsDelegates,
      home: FoodAdminScreen(auth: auth),
    );

void _tall(WidgetTester t, {double width = 900}) {
  t.view.physicalSize = Size(width, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

void main() {
  testWidgets('overview shows the numbers the server returned', (tester) async {
    _tall(tester);
    await tester.pumpWidget(_app(_AdminSession()));
    await tester.pumpAndSettle();
    expect(find.text('7 / 8'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('Самовывоз'), findsOneWidget);
    expect(find.byKey(const Key('food-admin-empty')), findsNothing);
  });

  testWidgets('empty period shows zeros and an explicit empty state',
      (tester) async {
    _tall(tester);
    await tester.pumpWidget(_app(_AdminSession(empty: true)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('food-admin-empty')), findsOneWidget);
    expect(find.text('0 / 0'), findsOneWidget);
    // No sample figure from the design reference leaks into an empty database.
    expect(find.textContaining('42 680'), findsNothing);
    expect(find.textContaining('326'), findsNothing);
  });

  testWidgets('refund asks for a reason and calls the admin API',
      (tester) async {
    _tall(tester);
    final session = _AdminSession();
    await tester.pumpWidget(_app(session));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, 'Заказы'));
    await tester.pumpAndSettle();
    expect(find.textContaining('abcd1234'), findsOneWidget);
    await tester.tap(find.byKey(const Key('food-admin-refund')));
    await tester.pumpAndSettle();
    // A reason shorter than 3 characters sends nothing.
    await tester.enterText(find.byKey(const Key('food-admin-reason')), 'x');
    await tester.tap(find.text('Подтвердить'));
    await tester.pumpAndSettle();
    expect(session.calls, isNot(contains('POST admin/food/orders/o-1/refund')));
    await tester.tap(find.byKey(const Key('food-admin-refund')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('food-admin-reason')), 'Тестовый возврат');
    await tester.tap(find.text('Подтвердить'));
    await tester.pumpAndSettle();
    final index = session.calls.indexOf('POST admin/food/orders/o-1/refund');
    expect(index, greaterThan(-1));
    expect(session.bodies[index], {'reason': 'Тестовый возврат'});
  });

  testWidgets('blocking a restaurant sends decision and reason',
      (tester) async {
    _tall(tester);
    final session = _AdminSession();
    await tester.pumpWidget(_app(session));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, 'Рестораны'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Блок'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('food-admin-reason')), 'Проверка документов');
    await tester.tap(find.text('Подтвердить'));
    await tester.pumpAndSettle();
    final index =
        session.calls.indexOf('POST admin/food/restaurants/r-1/moderation');
    expect(session.bodies[index],
        {'decision': 'BLOCK', 'reason': 'Проверка документов'});
  });

  for (final width in [320.0, 360.0]) {
    testWidgets('overview fits $width dp at 200% text', (tester) async {
      _tall(tester, width: width);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await tester.pumpWidget(_app(_AdminSession()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
