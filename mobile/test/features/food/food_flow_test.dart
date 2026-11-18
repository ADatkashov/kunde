import 'dart:convert';
import 'package:kunde_mobile/features/home/presentation/home_screen.dart';
import 'package:kunde_mobile/features/home/data/kunde_api.dart';
import 'package:kunde_mobile/features/shell/tabs.dart';
import 'package:kunde_mobile/core/localization/kunde_localizations.dart';
import '../../support/premium_goldens.dart';
import 'package:kunde_mobile/shared/theme/kunde_theme.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_mobile/features/food/data/cart_controller.dart';
import 'package:kunde_mobile/features/food/data/food_api.dart';
import 'package:kunde_mobile/features/food/data/food_models.dart';
import 'package:kunde_mobile/features/food/food_services.dart';
import 'package:kunde_mobile/features/food/presentation/food_home_screen.dart';
import 'package:kunde_mobile/features/food/presentation/checkout_screen.dart';
import 'package:kunde_mobile/features/food/presentation/order_screen.dart';
import 'package:kunde_mobile/features/food/presentation/orders_tab.dart';
import 'package:kunde_mobile/features/identity/auth_repository.dart';

class _Vault implements TokenVault {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async {}
  @override
  Future<void> clear() async {}
}

class _Gateway implements OAuthGateway {
  @override
  Future<AuthTokens> login({bool register = false}) async => AuthTokens(
      'access',
      'refresh',
      null,
      DateTime.now().add(const Duration(minutes: 5)));
  @override
  Future<AuthTokens> refresh(String refreshToken) => login();
  @override
  Future<void> logout(String? idToken) async {}
}

const _restaurantId = '11111111-1111-1111-1111-111111111111';
const _dishId = '22222222-2222-2222-2222-222222222222';
const _sizeS = '33333333-3333-3333-3333-333333333331';
const _sizeL = '33333333-3333-3333-3333-333333333332';
const _addressId = '44444444-4444-4444-4444-444444444444';

Map<String, dynamic> _restaurant({int minOrder = 0}) => {
      'id': _restaurantId,
      'slug': 'pizza',
      'name': 'Пицца Тест',
      'cuisine': 'Итальянская',
      'description': 'Вымышленный ресторан',
      'emoji': '🍕',
      'tone': 'red',
      'deliveryFeeMinor': 60000,
      'minOrderMinor': minOrder,
      'etaMinMinutes': 30,
      'etaMaxMinutes': 45,
      'open': true,
      'synthetic': true,
    };

final _menu = {
  'restaurant': _restaurant(),
  'sections': [
    {
      'id': 's1',
      'name': 'Пицца',
      'dishes': [
        {
          'id': _dishId,
          'name': 'Маргарита',
          'description': 'Томаты, моцарелла',
          'priceMinor': 350000,
          'emoji': '🍕',
          'tone': 'red',
          'available': true,
          'optionGroups': [
            {
              'id': 'g1',
              'name': 'Размер',
              'minSelect': 1,
              'maxSelect': 1,
              'options': [
                {'id': _sizeS, 'name': '25 см', 'priceDeltaMinor': 0},
                {'id': _sizeL, 'name': '35 см', 'priceDeltaMinor': 280000},
              ],
            },
          ],
        },
      ],
    },
  ],
};

/// In-memory stand-in for the Food backend: it re-prices on the "server" and keeps orders across app restarts.
class _FakeBackend {
  final orders = <Map<String, dynamic>>[];
  final keys = <String, String>{};
  bool offline = false;
  bool withClosedRestaurant = false;
  bool flowersCatalog = false;
  final requestedVerticals = <String?>[];
  int minOrder = 0;

  http.Response _json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status,
          headers: {'content-type': 'application/json; charset=utf-8'});

  Future<http.Response> handle(http.Request request) async {
    if (offline) throw http.ClientException('offline');
    final path = request.url.path.replaceFirst('/api/v1/', '');
    final body = request.body.isEmpty
        ? null
        : jsonDecode(request.body) as Map<String, dynamic>;
    if (path == 'food/restaurants') {
      requestedVerticals.add(request.url.queryParameters['vertical']);
      if (request.url.queryParameters['vertical'] == 'FLOWERS_GIFTS' &&
          flowersCatalog) {
        return _json([
          {..._restaurant(), 'vertical': 'FLOWERS_GIFTS'}
        ]);
      }
      if (request.url.queryParameters['vertical'] == 'GROCERY') {
        return _json([
          {
            ..._restaurant(),
            'id': '55555555-5555-5555-5555-555555555555',
            'name': 'Маркет Тест',
            'cuisine': 'Супермаркет',
            'emoji': '🛒',
            'vertical': 'GROCERY',
          }
        ]);
      }
      return _json([
        _restaurant(minOrder: minOrder),
        if (withClosedRestaurant)
          {
            ..._restaurant(),
            'id': '66666666-6666-6666-6666-666666666666',
            'name': 'Закрытая Пиццерия',
            'open': false,
          },
      ]);
    }
    if (path == 'food/restaurants/$_restaurantId') {
      return _json({
        ..._menu,
        'restaurant': {
          ..._restaurant(minOrder: minOrder),
          if (flowersCatalog) 'vertical': 'FLOWERS_GIFTS'
        }
      });
    }
    if (path == 'food/search') return _json({'restaurants': [], 'dishes': []});
    if (path == 'me/addresses') {
      return _json([
        {
          'id': _addressId,
          'label': 'Дом',
          'formattedAddress': 'Алматы, Абая 10',
          'version': 0
        }
      ]);
    }
    if (path == 'food/cart/quote') {
      final quote = _price(body!);
      if (quote == null) return _json({'code': 'FOOD_OPTIONS_INVALID'}, 422);
      return _json(quote);
    }
    if (path == 'food/orders' && request.method == 'POST') {
      final key = request.headers['Idempotency-Key']!;
      if (keys.containsKey(key)) {
        return _json(orders.firstWhere((o) => o['id'] == keys[key]));
      }
      final quote = _price(body!)!;
      final order = {
        'id': 'aaaaaaaa-0000-0000-0000-00000000000${orders.length + 1}',
        'restaurantId': _restaurantId,
        'restaurantName': 'Пицца Тест',
        if (flowersCatalog) 'vertical': 'FLOWERS_GIFTS',
        'status': 'PLACED',
        'paymentMethod': body['paymentMethod'],
        'paymentStatus': body['paymentMethod'] == 'DEV_NO_PAYMENT'
            ? 'NO_PAYMENT'
            : body['paymentMethod'] == 'TEST_CARD'
                ? 'TEST_PAID'
                : 'PAY_ON_RECEIPT',
        'subtotalMinor': quote['subtotalMinor'],
        'deliveryFeeMinor': quote['deliveryFeeMinor'],
        'totalMinor': quote['totalMinor'],
        'addressLabel': 'Дом',
        'addressText': 'Алматы, Абая 10',
        'comment': body['comment'],
        'placedAt': DateTime.now().toUtc().toIso8601String(),
        'items': [
          for (final l in quote['lines'] as List)
            {
              'name': (l as Map)['name'],
              'optionsText': l['optionsText'],
              'quantity': l['quantity'],
              'lineTotalMinor': l['lineTotalMinor'],
            }
        ],
        'timeline': [
          {'status': 'PLACED', 'at': DateTime.now().toUtc().toIso8601String()}
        ],
        'cancellable': true,
      };
      orders.insert(0, order);
      keys[key] = order['id'] as String;
      return _json(order, 201);
    }
    if (path == 'food/orders') return _json(orders);
    if (path.startsWith('food/orders/')) {
      final id = path.split('/')[2];
      return _json(orders.firstWhere((o) => o['id'] == id));
    }
    return http.Response('not found', 404);
  }

  Map<String, dynamic>? _price(Map<String, dynamic> body) {
    var subtotal = 0;
    final lines = <Map<String, dynamic>>[];
    for (final item in body['items'] as List) {
      final options = (item['optionIds'] as List).cast<String>();
      if (options.length != 1) return null;
      final unit = 350000 + (options.first == _sizeL ? 280000 : 0);
      final qty = item['quantity'] as int;
      lines.add({
        'dishId': _dishId,
        'name': 'Маргарита',
        'optionsText': options.first == _sizeL ? '35 см' : '25 см',
        'optionIds': options,
        'unitPriceMinor': unit,
        'quantity': qty,
        'lineTotalMinor': unit * qty,
      });
      subtotal += unit * qty;
    }
    return {
      'restaurantId': _restaurantId,
      'restaurantName': 'Пицца Тест',
      'lines': lines,
      'subtotalMinor': subtotal,
      'deliveryFeeMinor': 60000,
      'totalMinor': subtotal + 60000,
      'currency': 'KZT',
      'minOrderMinor': minOrder,
    };
  }
}

Future<FoodServices> _services(
    _FakeBackend backend, WidgetTester tester) async {
  final auth = AuthRepository(
    gateway: _Gateway(),
    vault: _Vault(),
    apiBase: Uri.parse('https://api.example.test/api/v1/'),
    client: MockClient(backend.handle),
  );
  await auth.signIn(AuthTokens('access', 'refresh', null,
      DateTime.now().add(const Duration(minutes: 5))));
  addTearDown(auth.dispose);
  return FoodServices(
    api: FoodApi(
        baseUri: Uri.parse('https://api.example.test/api/v1/'),
        auth: auth,
        client: MockClient(backend.handle)),
    cart: CartController(),
    auth: auth,
  );
}

Future<void> _show(WidgetTester tester, Widget home,
    {Size size = const Size(1080, 2200),
    double pixelRatio = 2.75,
    double textScale = 1,
    Locale? locale}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = pixelRatio;
  addTearDown(tester.view.reset);
  // Tear the previous app down completely (like a process restart) before showing the next one.
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: KundeTheme.light,
      locale: locale,
      supportedLocales: KundeLocalizations.supportedLocales,
      localizationsDelegates: KundeLocalizations.localizationsDelegates,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!),
      home: home));
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [360.0, 390.0, 412.0]) {
    for (final vertical in ['FOOD', 'GROCERY', 'FLOWERS_GIFTS']) {
      testWidgets('Samsung $width $vertical large text layout', (tester) async {
        await tester.runAsync(loadPremiumFonts);
        final services = await _services(_FakeBackend(), tester);
        await _show(
            tester, FoodHomeScreen(services: services, vertical: vertical),
            size: Size(width, 844), pixelRatio: 1, textScale: 2);
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(ListView).last, const Offset(0, -600));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final entry in {
    'ru': 'Цветы и подарки',
    'kk': 'Гүлдер мен сыйлықтар',
    'en': 'Flowers & gifts',
  }.entries) {
    testWidgets('flowers catalog requests its vertical in ${entry.key}',
        (tester) async {
      final backend = _FakeBackend();
      final services = await _services(backend, tester);
      await _show(
          tester, FoodHomeScreen(services: services, vertical: 'FLOWERS_GIFTS'),
          locale: Locale(entry.key));
      expect(backend.requestedVerticals, contains('FLOWERS_GIFTS'));
      expect(find.text(entry.value), findsOneWidget);
    });
  }

  testWidgets('flowers store to test order and history', (tester) async {
    final backend = _FakeBackend()..flowersCatalog = true;
    final services = await _services(backend, tester);
    await _show(
        tester, FoodHomeScreen(services: services, vertical: 'FLOWERS_GIFTS'));
    await tester.tap(find.text('Пицца Тест'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Маргарита'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Add ·'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Cart · 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Checkout ·'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.textContaining('Confirm order'), 300,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.textContaining('Confirm order'));
    await tester.pumpAndSettle();
    expect(backend.orders.single['paymentMethod'], 'DEV_NO_PAYMENT');
    expect(find.text('Test order created'), findsWidgets);
    await _show(tester, Scaffold(body: FoodOrdersTab(services: services)));
    expect(find.text('Пицца Тест'), findsOneWidget);
  });

  testWidgets('flowers checkout submits no payment', (tester) async {
    final backend = _FakeBackend();
    final services = await _services(backend, tester);
    services.cart.add(
        Restaurant.fromJson({..._restaurant(), 'vertical': 'FLOWERS_GIFTS'}),
        CartLine(
            dishId: _dishId,
            name: 'Маргарита',
            emoji: '💐',
            tone: 'red',
            optionIds: const [_sizeS],
            optionsText: '',
            unitPriceMinor: 350000,
            quantity: 1));
    final quote = FoodQuote.fromJson(backend._price({
      'items': [
        {
          'dishId': _dishId,
          'quantity': 1,
          'optionIds': [_sizeS]
        }
      ]
    })!);
    await _show(tester, CheckoutScreen(services: services, quote: quote));
    expect(find.textContaining('No payment or real delivery'), findsWidgets);
    expect(find.text('Тестовая карта (DEV)'), findsNothing);
    await tester.ensureVisible(find.textContaining('Confirm order'));
    await tester.tap(find.textContaining('Confirm order'));
    await tester.pumpAndSettle();
    expect(backend.orders.single['paymentMethod'], 'DEV_NO_PAYMENT');
  });

  for (final entry in {
    'ru': 'Подтвердить заказ',
    'kk': 'Тапсырысты растау',
    'en': 'Confirm order',
  }.entries) {
    testWidgets('flowers checkout language ${entry.key}', (tester) async {
      final backend = _FakeBackend();
      final services = await _services(backend, tester);
      services.cart.add(
          Restaurant.fromJson({..._restaurant(), 'vertical': 'FLOWERS_GIFTS'}),
          CartLine(
              dishId: _dishId,
              name: 'Test',
              emoji: '💐',
              tone: 'red',
              optionIds: const [_sizeS],
              optionsText: '',
              unitPriceMinor: 350000,
              quantity: 1));
      final quote = FoodQuote.fromJson(backend._price({
        'items': [
          {
            'dishId': _dishId,
            'quantity': 1,
            'optionIds': [_sizeS]
          }
        ]
      })!);
      await _show(tester, CheckoutScreen(services: services, quote: quote),
          locale: Locale(entry.key));
      await tester.ensureVisible(find.textContaining(entry.value));
      expect(find.textContaining(entry.value), findsOneWidget);
      expect(find.text('Тестовая карта (DEV)'), findsNothing);
    });
  }

  testWidgets('premium golden complete home with nearby merchants',
      (tester) async {
    await tester.runAsync(loadPremiumFonts);
    final services = await _services(_FakeBackend(), tester);
    final api = KundeApi(
        baseUri: Uri.parse('https://api.example.test/api/v1/'),
        client: MockClient((_) async => http.Response(
            jsonEncode({
              'releaseStage': 'DEV',
              'marketplaceEnabled': true,
              'oidcIssuerConfigured': false,
              'aiEnabled': false,
            }),
            200)));
    addTearDown(api.close);
    tester.view.physicalSize = const Size(390, 1250);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: KundeTheme.light,
        locale: const Locale('ru'),
        localizationsDelegates: KundeLocalizations.localizationsDelegates,
        supportedLocales: KundeLocalizations.supportedLocales,
        home: Scaffold(
            body: HomeScreen(api: api, food: services),
            bottomNavigationBar: KundeNavigationBar(
                selected: KundeTab.home, onSelected: (_) {}))));
    await premiumGolden(tester, 'premium_home_nearby');
  });

  testWidgets('catalog filters real API results by availability and query',
      (tester) async {
    final backend = _FakeBackend()..withClosedRestaurant = true;
    final services = await _services(backend, tester);
    final api = KundeApi(
      baseUri: Uri.parse('https://api.example.test/api/v1/'),
      client: MockClient((_) async => http.Response(
          jsonEncode({
            'releaseStage': 'DEV',
            'marketplaceEnabled': true,
            'oidcIssuerConfigured': false,
            'aiEnabled': false,
          }),
          200)),
    );
    addTearDown(api.close);

    await _show(tester, Scaffold(body: SearchTab(api: api, food: services)),
        locale: const Locale('ru'), size: const Size(390, 1000), pixelRatio: 1);
    final closed = find.text('Закрытая Пиццерия');
    expect(closed, findsOneWidget);
    await tester.tap(find.text('Открыто сейчас'));
    await tester.pumpAndSettle();
    expect(closed, findsNothing);
    expect(find.text('Пицца Тест'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Суши');
    await tester.pumpAndSettle();
    expect(find.text('Пицца Тест'), findsNothing);
    expect(
        find.text(KundeLocalizations.of(tester.element(find.byType(SearchTab)))
            .searchEmpty),
        findsOneWidget);
    expect(backend.requestedVerticals, hasLength(1));
  });

  testWidgets('premium golden Food and Grocery Samsung', (tester) async {
    await tester.runAsync(loadPremiumFonts);
    final services = await _services(_FakeBackend(), tester);
    await _show(tester, FoodHomeScreen(services: services));
    await premiumGolden(tester, 'premium_food');
    await _show(
        tester, FoodHomeScreen(services: services, vertical: 'GROCERY'));
    await premiumGolden(tester, 'premium_grocery');
  });

  testWidgets('premium golden cart checkout and history', (tester) async {
    await tester.runAsync(loadPremiumFonts);
    final backend = _FakeBackend();
    final services = await _services(backend, tester);
    await _show(tester, FoodHomeScreen(services: services));
    await tester.tap(find.text('Пицца Тест'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Маргарита'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Добавить ·'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Корзина · 1'));
    await premiumGolden(tester, 'premium_cart');
    await tester.tap(find.textContaining('Оформить заказ'));
    await premiumGolden(tester, 'premium_checkout');
    await _show(tester, Scaffold(body: FoodOrdersTab(services: services)));
    await premiumGolden(tester, 'premium_history_empty');
    // A deterministic order date keeps the populated history baseline stable.
    await backend.handle(http.Request(
        'POST', Uri.parse('https://api.example.test/api/v1/food/orders'))
      ..headers['Idempotency-Key'] = 'golden-history'
      ..body = jsonEncode({
        'restaurantId': _restaurantId,
        'addressId': _addressId,
        'paymentMethod': 'CASH_ON_DELIVERY',
        'items': [
          {
            'dishId': _dishId,
            'quantity': 1,
            'optionIds': [_sizeS]
          }
        ]
      }));
    backend.orders.single['placedAt'] = '2026-11-15T09:41:00Z';
    await _show(tester, Scaffold(body: FoodOrdersTab(services: services)));
    await premiumGolden(tester, 'premium_history');
  });

  test('flowers statuses describe synthetic fulfilment', () {
    expect(flowersStatusLabel('DELIVERED', 'ru'), contains('Тестовая'));
    expect(flowersStatusLabel('DELIVERED', 'kk'), contains('Сынақ'));
    expect(flowersStatusLabel('DELIVERED', 'en'), contains('Test'));
  });

  test('price changes are explained in all checkout languages', () {
    const error = FoodException(FoodFailure.priceChanged);
    expect(error.messageFor('ru'), contains('Цена изменилась'));
    expect(error.messageFor('kk'), contains('Баға өзгерді'));
    expect(error.messageFor('en'), contains('price changed'));
  });

  test('formatTenge groups thousands and hides zero tiyn', () {
    expect(formatTenge(350000), '3 500 ₸');
    expect(formatTenge(1220000), '12 200 ₸');
    expect(formatTenge(250050), '2 500,50 ₸');
    expect(formatTenge(0), '0 ₸');
  });

  test('cart keeps one restaurant, merges identical lines and caps quantity',
      () {
    final cart = CartController();
    final a = Restaurant.fromJson(_restaurant());
    CartLine line(int qty, {List<String> options = const [_sizeS]}) => CartLine(
        dishId: _dishId,
        name: 'Маргарита',
        emoji: '🍕',
        tone: 'red',
        optionIds: options,
        optionsText: '',
        unitPriceMinor: 100,
        quantity: qty);
    cart.add(a, line(2));
    cart.add(a, line(3));
    expect(cart.lines, hasLength(1));
    expect(cart.itemCount, 5);
    cart.add(a, line(1, options: const [_sizeL]));
    expect(cart.lines, hasLength(2));
    cart.setQuantity(cart.lines.first, 99);
    expect(cart.lines.first.quantity, CartController.maxLineQuantity);
    expect(cart.conflictsWith('other'), isTrue);
    cart.setQuantity(cart.lines.first, 0);
    cart.setQuantity(cart.lines.first, 0);
    expect(cart.isEmpty, isTrue);
    expect(cart.restaurant, isNull);
  });

  testWidgets(
      'customer orders a dish and still sees the order after restarting the app',
      (tester) async {
    final backend = _FakeBackend();
    final services = await _services(backend, tester);
    await _show(tester, FoodHomeScreen(services: services));

    expect(find.text('Пицца Тест'), findsOneWidget);
    expect(find.text('ДЕМО'), findsOneWidget);
    await tester.tap(find.text('Пицца Тест'));
    await tester.pumpAndSettle();
    expect(find.text('Маргарита'), findsOneWidget);

    await tester.tap(find.text('Маргарита'));
    await tester.pumpAndSettle();
    // Required size defaults to the first option; choose the large one and add two pizzas.
    await tester.tap(find.text('35 см'));
    await tester.pump();
    await tester.tap(find.byTooltip('Больше'));
    await tester.pump();
    expect(find.textContaining('Добавить · 12 600 ₸'), findsOneWidget);
    await tester.tap(find.textContaining('Добавить ·'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Корзина · 2'), findsOneWidget);

    await tester.tap(find.textContaining('Корзина · 2'));
    await tester.pumpAndSettle();
    expect(find.text('Итого'), findsOneWidget);
    expect(find.text('13 200 ₸'), findsWidgets);
    await tester.tap(find.textContaining('Оформить заказ'));
    await tester.pumpAndSettle();

    expect(find.text('Дом'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -900));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Подтвердить заказ').last);
    await tester.pumpAndSettle();
    expect(find.text('Заказ принят!'), findsOneWidget);
    expect(find.text('Заказ оформлен'), findsWidgets);
    expect(backend.orders, hasLength(1));
    expect(backend.orders.single['totalMinor'], 1320000);
    expect(services.cart.isEmpty, isTrue);

    // "Restart": a brand-new app state with an empty cart restores the history from the server.
    final restarted = await _services(backend, tester);
    await _show(tester, Scaffold(body: FoodOrdersTab(services: restarted)));
    expect(find.text('My orders'), findsOneWidget);
    expect(find.textContaining('Пицца Тест'), findsOneWidget);
    expect(find.textContaining('2× Маргарита'), findsOneWidget);
  });

  testWidgets('orders tab shows an empty state and an offline error with retry',
      (tester) async {
    final backend = _FakeBackend();
    final services = await _services(backend, tester);
    await _show(tester,
        Scaffold(body: FoodOrdersTab(key: UniqueKey(), services: services)));
    expect(find.text('No orders yet'), findsOneWidget);

    backend.offline = true;
    await _show(tester,
        Scaffold(body: FoodOrdersTab(key: UniqueKey(), services: services)));
    expect(find.text('Не удалось загрузить заказы'), findsOneWidget);
    backend.offline = false;
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();
    expect(find.text('No orders yet'), findsOneWidget);
  });

  testWidgets('catalog shows a retryable error when the server is unreachable',
      (tester) async {
    final backend = _FakeBackend()..offline = true;
    final services = await _services(backend, tester);
    await _show(tester, FoodHomeScreen(services: services));
    expect(find.text('Не удалось загрузить рестораны'), findsOneWidget);
    backend.offline = false;
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();
    expect(find.text('Пицца Тест'), findsOneWidget);
  });

  testWidgets('grocery vertical lists stores, not restaurants', (tester) async {
    final backend = _FakeBackend();
    final services = await _services(backend, tester);
    await _show(
        tester, FoodHomeScreen(services: services, vertical: 'GROCERY'));
    expect(find.text('Продукты · Алматы'), findsOneWidget);
    expect(find.text('Маркет Тест'), findsOneWidget);
    expect(find.text('Пицца Тест'), findsNothing);
    expect(find.text('Магазины и товары'), findsOneWidget);
    expect(backend.requestedVerticals, contains('GROCERY'));
  });

  test('vertical defaults to FOOD in the models', () {
    expect(Restaurant.fromJson(_restaurant()).vertical, 'FOOD');
    expect(
        Restaurant.fromJson({..._restaurant(), 'vertical': 'GROCERY'}).vertical,
        'GROCERY');
  });

  test('weighed goods use grams, step 100 g and kilogram formatting', () {
    expect(formatQuantity('KG', 500), '500 г');
    expect(formatQuantity('KG', 1500), '1,5 кг');
    expect(formatQuantity('KG', 2000), '2 кг');
    expect(formatQuantity('PIECE', 3), '3 шт');
    expect(unitPriceLabel('KG', 599000), '5\u00A0990\u00A0₸ / кг');
    // 1.5 kg at 5 990 KZT/kg = 8 985 KZT; rounds half up like the server.
    expect(lineTotalMinor('KG', 599000, 1500), 898500);
    expect(lineTotalMinor('KG', 33, 100), 3);
    expect(lineTotalMinor('PIECE', 62000, 8), 496000);

    final cart = CartController();
    final store =
        Restaurant.fromJson({..._restaurant(), 'vertical': 'GROCERY'});
    final line = CartLine(
        dishId: _dishId,
        name: 'Говядина',
        emoji: '🥩',
        tone: 'red',
        optionIds: const [],
        optionsText: '',
        unitPriceMinor: 599000,
        quantity: 500,
        unit: 'KG',
        maxQuantity: 3000);
    cart.add(store, line);
    expect(cart.itemCount, 1);
    cart.setQuantity(line, line.quantity + line.step);
    expect(line.quantity, 600);
    cart.setQuantity(line, 9000);
    expect(line.quantity, 3000, reason: 'capped at stock');
    cart.setQuantity(line, line.quantity - line.step * 40);
    expect(cart.isEmpty, isTrue);
    expect(
        CartLine(
            dishId: 'a',
            name: 'x',
            emoji: '',
            tone: 'red',
            optionIds: const [],
            optionsText: '',
            unitPriceMinor: 1,
            quantity: 1,
            substitution: 'CHOSEN',
            substituteDishIds: const ['b']).toRequest(),
        containsPair('substitution', 'CHOSEN'));
  });

  testWidgets('catalog filters hide closed restaurants and filter by cuisine',
      (tester) async {
    final backend = _FakeBackend()..withClosedRestaurant = true;
    final services = await _services(backend, tester);
    await _show(tester, FoodHomeScreen(services: services),
        size: const Size(640, 800), pixelRatio: 1);
    expect(find.text('Закрытая Пиццерия'), findsOneWidget);
    await tester.tap(find.text('Открыто сейчас'));
    await tester.pumpAndSettle();
    expect(find.text('Закрытая Пиццерия'), findsNothing);
    expect(find.text('Пицца Тест'), findsOneWidget);
    final cuisine = find.widgetWithText(ChoiceChip, 'Итальянская');
    await tester.tap(cuisine);
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(cuisine).selected, isTrue);
    expect(find.text('Пицца Тест'), findsOneWidget);
  });

  testWidgets('cancelled flowers order does not claim a payment was voided',
      (tester) async {
    final backend = _FakeBackend();
    backend.orders.add({
      'id': 'cccccccc-0000-0000-0000-000000000001',
      'restaurantId': _restaurantId,
      'restaurantName': 'Flowers',
      'status': 'CANCELLED',
      'paymentMethod': 'DEV_NO_PAYMENT',
      'paymentStatus': 'NO_PAYMENT',
      'subtotalMinor': 100,
      'deliveryFeeMinor': 0,
      'totalMinor': 100,
      'vertical': 'FLOWERS_GIFTS',
      'addressLabel': 'Test',
      'addressText': 'Test',
      'comment': null,
      'placedAt': DateTime.now().toUtc().toIso8601String(),
      'cancellable': false,
      'cancelledBy': 'PARTNER',
      'cancelReason': 'Test',
      'timeline': <Map<String, dynamic>>[],
      'items': <Map<String, dynamic>>[],
    });
    final services = await _services(backend, tester);
    await _show(
        tester,
        OrderScreen(
            services: services,
            orderId: 'cccccccc-0000-0000-0000-000000000001'));
    expect(find.textContaining('No payment was made.'), findsOneWidget);
    expect(find.textContaining('Reason: Test'), findsOneWidget);
    expect(find.textContaining('Платёж аннулирован'), findsNothing);
  });

  testWidgets(
      'order screen shows replaced and removed lines and the final total',
      (tester) async {
    final backend = _FakeBackend();
    backend.orders.add({
      'id': 'bbbbbbbb-0000-0000-0000-000000000001',
      'restaurantId': _restaurantId,
      'restaurantName': 'Маркет Тест',
      'status': 'DELIVERED',
      'paymentMethod': 'CASH_ON_DELIVERY',
      'paymentStatus': 'PAY_ON_RECEIPT',
      'subtotalMinor': 952000,
      'deliveryFeeMinor': 60000,
      'totalMinor': 1012000,
      'finalTotalMinor': 580000,
      'hasChanges': true,
      'vertical': 'GROCERY',
      'addressLabel': 'Дом',
      'addressText': 'Алматы, Абая 10',
      'comment': null,
      'placedAt': DateTime.now().toUtc().toIso8601String(),
      'cancellable': false,
      'timeline': [
        {'status': 'PLACED', 'at': DateTime.now().toUtc().toIso8601String()}
      ],
      'items': [
        {
          'name': 'Кефир 0,9 л',
          'optionsText': '',
          'quantity': 8,
          'unit': 'PIECE',
          'lineTotalMinor': 432000,
          'substitution': 'CHOSEN',
          'fulfillmentStatus': 'SUBSTITUTED',
          'replacedByName': 'Молоко 1 л',
          'finalLineTotalMinor': 432000,
        },
        {
          'name': 'Говядина вырезка',
          'optionsText': '',
          'quantity': 1500,
          'unit': 'KG',
          'lineTotalMinor': 898500,
          'substitution': 'NONE',
          'fulfillmentStatus': 'REMOVED',
          'finalLineTotalMinor': 0,
        },
      ],
    });
    final services = await _services(backend, tester);
    await _show(
        tester,
        OrderScreen(
            services: services,
            orderId: 'bbbbbbbb-0000-0000-0000-000000000001'));
    expect(find.text('Заменено на: Молоко 1 л'), findsOneWidget);
    expect(find.text('Нет в наличии — убрано из заказа'), findsOneWidget);
    expect(find.textContaining('1,5 кг Говядина вырезка'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.text('Итого с учётом изменений'), findsOneWidget);
    expect(find.text('5\u00A0800\u00A0₸'), findsWidgets);
  });
}
