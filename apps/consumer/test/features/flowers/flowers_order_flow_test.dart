import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_auth/auth_repository.dart';
import 'package:kunde_mobile/features/flowers/data/flowers_cart.dart';
import 'package:kunde_mobile/features/flowers/data/flowers_models.dart';
import 'package:kunde_mobile/features/flowers/data/flowers_services.dart';
import 'package:kunde_mobile/features/flowers/presentation/flowers_order_screen.dart';
import 'package:kunde_mobile/features/flowers/presentation/flowers_shop_screen.dart';
import 'package:kunde_mobile/features/home/data/kunde_api.dart';

const _slotIso = '2026-11-30T07:00:00Z';

/// The client sends the offered instant as a normalised UTC string; the server compares instants, not text.
const _slotSent = '2026-11-30T07:00:00.000Z';

Map<String, dynamic> _orderJson(String status, {String mode = 'ASAP'}) => {
      'id': 'abcdef12-0000-0000-0000-000000000001',
      'shopId': 's1',
      'shopName': 'Цветочная лавка',
      'status': status,
      'paymentMethod': 'DEV_NO_PAYMENT',
      'paymentStatus': 'NO_PAYMENT',
      'subtotalMinor': 1790000,
      'deliveryFeeMinor': 100000,
      'totalMinor': 1890000,
      'deliveryMode': mode,
      'scheduledFrom': mode == 'SCHEDULED' ? _slotIso : null,
      'scheduledTo': mode == 'SCHEDULED' ? '2026-11-30T09:00:00Z' : null,
      'addressLabel': '',
      'addressText': 'ул. Абая, 150, кв. 45',
      'recipientName': 'Айгуль',
      'cardText': 'С днём рождения!',
      'comment': null,
      'placedAt': '2026-11-27T08:00:00Z',
      'items': [
        {
          'productId': 'p1',
          'name': 'Букет «Классика»',
          'emoji': '🌹',
          'unitPriceMinor': 1790000,
          'quantity': 1,
          'lineTotalMinor': 1790000,
        }
      ],
      'events': [],
    };

class _Auth implements AuthRepository {
  final calls = <String>[];
  final bodies = <Map<String, dynamic>?>[];
  final keys = <String?>[];
  String status = 'PLACED';
  int? failPlaceWith;
  String? failCode;

  @override
  Future<dynamic> authorizedJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Set<int> expected = const {200},
    Map<String, String>? headers,
  }) async {
    calls.add('$method $path');
    bodies.add(body);
    keys.add(headers?['Idempotency-Key']);
    if (path == 'flowers/cart/quote') {
      return {
        'lines': [
          {
            'productId': 'p1',
            'name': 'Букет «Классика»',
            'emoji': '🌹',
            'unitPriceMinor': 1790000,
            'quantity': 1,
            'lineTotalMinor': 1790000,
          }
        ],
        'subtotalMinor': 1790000,
        'deliveryFeeMinor': 100000,
        'totalMinor': 1890000,
      };
    }
    if (method == 'POST' && path == 'flowers/orders') {
      if (failPlaceWith != null) {
        throw IdentityApiError(failPlaceWith!, failCode);
      }
      return _orderJson('PLACED', mode: body!['deliveryMode'] as String);
    }
    if (path.endsWith('/cancel')) {
      return _orderJson('CANCELLED');
    }
    if (path.startsWith('flowers/orders/')) return _orderJson(status);
    return [_orderJson(status)];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<http.Response> _public(http.Request r) async {
  Object body;
  switch (r.url.path) {
    case '/api/v1/flowers/shops/s1':
      body = {
        'shop': {
          'id': 's1',
          'slug': 's1',
          'name': 'Цветочная лавка',
          'description': '',
          'emoji': '💐',
          'tone': 'red',
          'imageUrl': null,
          'deliveryFeeMinor': 100000,
          'minOrderMinor': 0,
          'etaMinMinutes': 30,
          'etaMaxMinutes': 45,
          'open': true,
          'productCount': 1,
        },
        'products': [
          {
            'id': 'p1',
            'shopId': 's1',
            'shopName': 'Цветочная лавка',
            'categoryCode': 'BOUQUETS',
            'name': 'Букет «Классика»',
            'description': '25 роз',
            'priceMinor': 1790000,
            'emoji': '🌹',
            'tone': 'red',
            'imageUrl': null,
            'available': true,
            'stockQty': null,
            'popular': true,
          }
        ],
      };
    case '/api/v1/flowers/delivery-slots':
      body = [
        {'startsAt': _slotIso, 'endsAt': '2026-11-30T09:00:00Z'},
      ];
    default:
      return http.Response('{}', 404);
  }
  return http.Response(jsonEncode(body), 200,
      headers: {'content-type': 'application/json; charset=utf-8'});
}

Future<void> _open(
    WidgetTester tester, _Auth auth, FlowersServices services) async {
  tester.view.physicalSize = const Size(1080, 5200);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('en'),
    supportedLocales: const [Locale('en')],
    home: FlowersShopScreen(services: services, shopId: 's1'),
  ));
  await tester.pumpAndSettle();
}

FlowersServices _services(_Auth auth) => FlowersServices(
    api: KundeApi(
        baseUri: Uri.parse('https://api.example.test/api/v1/'),
        client: MockClient(_public)),
    auth: auth);

Future<void> _toCheckout(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('add-p1')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('cart-bar')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('checkout')));
  await tester.pumpAndSettle();
}

void main() {
  test('the cart keeps one shop, caps quantities and resets when emptied', () {
    final cart = FlowersCart();
    bool add(String shop, String product) => cart.add(
        shopId: shop,
        shopName: 'Магазин $shop',
        deliveryFeeMinor: 100000,
        productId: product,
        name: 'Товар $product',
        emoji: '🌹',
        unitPriceMinor: 500000);
    expect(add('s1', 'p1'), isTrue);
    expect(add('s1', 'p1'), isTrue);
    expect(cart.itemCount, 2);
    expect(cart.subtotalMinor, 1000000);
    expect(cart.conflictsWith('s2'), isTrue);
    expect(() => add('s2', 'p9'), throwsStateError);
    cart.setQuantity('p1', 99);
    expect(cart.lines.single.quantity, FlowersCart.maxLineQuantity);
    expect(add('s1', 'p1'), isFalse);
    expect(cart.toRequestItems(), [
      {'productId': 'p1', 'quantity': 20}
    ]);
    cart.setQuantity('p1', 0);
    expect(cart.isEmpty, isTrue);
    expect(cart.shopId, isNull);
  });

  test('order status maps to the four tracker steps', () {
    expect(flowersStep('PLACED'), 0);
    expect(flowersStep('ACCEPTED'), 0);
    expect(flowersStep('ASSEMBLING'), 1);
    expect(flowersStep('ON_THE_WAY'), 2);
    expect(flowersStep('DELIVERED'), 3);
    expect(flowersStep('CANCELLED'), isNull);
  });

  testWidgets(
      'add to cart, order as soon as possible, then cancel while placed',
      (tester) async {
    final auth = _Auth();
    final services = _services(auth);
    await _open(tester, auth, services);
    await _toCheckout(tester);

    // the server quote is what the customer confirms
    expect(find.text('18 900 ₸'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('submit')));
    await tester.pumpAndSettle();
    expect(find.text('Enter an address (5+ characters)'), findsOneWidget);
    expect(auth.calls.where((c) => c == 'POST flowers/orders'), isEmpty);

    await tester.enterText(
        find.byKey(const ValueKey('address')), 'ул. Абая, 150, кв. 45');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('submit')));
    await tester.pumpAndSettle();

    final index = auth.calls.indexOf('POST flowers/orders');
    expect(index, greaterThan(-1));
    expect(auth.bodies[index]!['deliveryMode'], 'ASAP');
    expect(auth.bodies[index]!['expectedTotalMinor'], 1890000);
    expect(auth.keys[index], isNotEmpty);
    expect(services.cart.isEmpty, isTrue);
    expect(find.text('Order placed'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cancelled')), findsOneWidget);
    expect(find.byKey(const ValueKey('cancel')), findsNothing);
  });

  testWidgets(
      'a scheduled order sends the chosen window and the quote follows it',
      (tester) async {
    final auth = _Auth();
    final services = _services(auth);
    await _open(tester, auth, services);
    await _toCheckout(tester);

    await tester.tap(find.byKey(const ValueKey('mode-SCHEDULED')));
    await tester.pumpAndSettle();
    expect(find.text('Pick a time to see the total'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('slot-$_slotSent')));
    await tester.pumpAndSettle();
    expect(find.text('18 900 ₸'), findsOneWidget);
    final quote = auth.calls.lastIndexOf('POST flowers/cart/quote');
    expect(auth.bodies[quote]!['deliveryMode'], 'SCHEDULED');
    expect(auth.bodies[quote]!['scheduledFrom'], _slotSent);

    await tester.enterText(
        find.byKey(const ValueKey('address')), 'ул. Абая, 150, кв. 45');
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('submit')));
    await tester.tap(find.byKey(const ValueKey('submit')));
    await tester.pumpAndSettle();
    final index = auth.calls.indexOf('POST flowers/orders');
    expect(auth.bodies[index]!['scheduledFrom'], _slotSent);
  });

  testWidgets('a changed price is explained and the order is not placed twice',
      (tester) async {
    final auth = _Auth()
      ..failPlaceWith = 409
      ..failCode = 'FLOWERS_PRICE_CHANGED';
    final services = _services(auth);
    await _open(tester, auth, services);
    await _toCheckout(tester);
    await tester.enterText(
        find.byKey(const ValueKey('address')), 'ул. Абая, 150, кв. 45');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('submit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('The price changed'), findsOneWidget);
    expect(services.cart.isEmpty, isFalse);
    // the quote is requested again
    expect(auth.calls.where((c) => c == 'POST flowers/cart/quote').length,
        greaterThan(1));
  });

  testWidgets('an order screen shows the tracker step of the status',
      (tester) async {
    final auth = _Auth();
    final services = _services(auth);
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: const [Locale('en')],
      home: Builder(builder: (context) {
        return FlowersOrderScreen(
            services: services,
            initial: FlowersOrder.fromJson(_orderJson('ON_THE_WAY')),
            every: const Duration(hours: 1));
      }),
    ));
    await tester.pumpAndSettle();
    expect(find.text('On the way'), findsOneWidget);
    expect(find.text('Order №ABCDEF12'), findsOneWidget);
    // not cancellable once the shop has started
    expect(find.byKey(const ValueKey('cancel')), findsNothing);
  });
}
