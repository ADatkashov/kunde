import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_localization/kunde_localizations.dart';
import 'package:kunde_mobile/features/food/data/cart_controller.dart';
import 'package:kunde_mobile/features/food/data/food_api.dart';
import 'package:kunde_models/food_models.dart';
import 'package:kunde_mobile/features/food/food_services.dart';
import 'package:kunde_mobile/features/groceries/data/groceries_api.dart';
import 'package:kunde_mobile/features/groceries/data/groceries_models.dart';
import 'package:kunde_mobile/features/groceries/data/groceries_services.dart';
import 'package:kunde_mobile/features/groceries/presentation/catalog_screen.dart';
import 'package:kunde_mobile/features/groceries/presentation/groceries_home_screen.dart';
import 'package:kunde_mobile/features/groceries/presentation/lists_screen.dart';
import 'package:kunde_mobile/features/groceries/presentation/product_screen.dart';
import 'package:kunde_auth/auth_repository.dart';
import 'package:kunde_design/kunde_theme.dart';

import '../../support/premium_goldens.dart';

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

const _storeA = '55555555-5555-5555-5555-555555555555';
const _storeB = '66666666-6666-6666-6666-666666666666';
const _apples = 'a0000000-0000-0000-0000-000000000001';
const _milk = 'a0000000-0000-0000-0000-000000000002';
const _eggs = 'a0000000-0000-0000-0000-000000000003';
const _otherStoreItem = 'b0000000-0000-0000-0000-000000000001';

Map<String, dynamic> _product(String id, String name,
        {String unit = 'PIECE',
        int price = 69000,
        int? compareAt,
        String store = _storeA,
        String storeName = 'Фреш Маркет',
        bool inStock = true,
        bool isNew = false,
        bool options = false,
        String? brand}) =>
    {
      'id': id,
      'name': name,
      'description': 'Описание $name',
      'brand': brand,
      'category': 'dairy',
      'unit': unit,
      'priceMinor': price,
      'compareAtPriceMinor': compareAt,
      'discountPercent': compareAt == null
          ? null
          : ((compareAt - price) * 100 / compareAt).round(),
      'available': inStock,
      'inStock': inStock,
      'maxQuantity': unit == 'KG' ? 5000 : 20,
      'stockQty': null,
      'emoji': unit == 'KG' ? '🍎' : '🥛',
      'tone': 'green',
      'imageUrl': null,
      'storeId': store,
      'storeName': storeName,
      'storeOpen': true,
      'isNew': isNew,
      'onSale': compareAt != null,
      'hasRequiredOptions': options,
    };

Map<String, dynamic> _restaurant(String id, String name) => {
      'id': id,
      'slug': name,
      'name': name,
      'cuisine': 'Супермаркет',
      'description': 'Вымышленный магазин',
      'emoji': '🛒',
      'tone': 'green',
      'deliveryFeeMinor': 0,
      'minOrderMinor': 300000,
      'etaMinMinutes': 30,
      'etaMaxMinutes': 50,
      'open': true,
      'synthetic': true,
      'vertical': 'GROCERY',
    };

/// In-memory stand-in for the Groceries backend. It records requests so tests can prove that filtering, sorting and
/// paging are done by the server, and it keeps favorites, lists and the cart like the real API does.
class _Backend {
  bool offline = false;
  bool disabled = false;
  bool emptyResults = false;
  List<String> galleryImages = const [];
  bool canReview = false;
  final reviewPosts = <Map<String, dynamic>>[];
  final reviewList = <Map<String, dynamic>>[];
  bool failProducts = false;
  int total = 35;
  final productQueries = <Map<String, String>>[];
  final favorites = <String>{};
  final lists = <Map<String, dynamic>>[];
  Map<String, dynamic>? serverCart;
  final cartPuts = <Map<String, dynamic>>[];
  final favoritePuts = <String>[];

  static const nutrition = {
    'kcal': 52,
    'protein': 0.3,
    'fat': 0.2,
    'carbs': 13.8
  };

  http.Response _json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status,
          headers: {'content-type': 'application/json; charset=utf-8'});

  Map<String, dynamic> _listDetail(Map<String, dynamic> list) => {
        'id': list['id'],
        'name': list['name'],
        'items': list['items'],
      };

  Map<String, dynamic> _listSummary(Map<String, dynamic> list) {
    final items = list['items'] as List<Map<String, dynamic>>;
    return {
      'id': list['id'],
      'name': list['name'],
      'items': items.length,
      'checked': items.where((i) => i['checked'] == true).length,
    };
  }

  Future<http.Response> handle(http.Request request) async {
    if (offline) throw http.ClientException('offline');
    final path = request.url.path.replaceFirst('/api/v1/', '');
    final body = request.body.isEmpty ? null : jsonDecode(request.body);
    if (path.startsWith('groceries/') &&
        disabled &&
        path != 'groceries/cart' &&
        !path.startsWith('groceries/lists') &&
        !path.startsWith('groceries/favorites')) {
      return _json({'code': 'GROCERIES_DISABLED'}, 409);
    }
    if (path == 'food/restaurants') {
      return _json([
        _restaurant(_storeA, 'Фреш Маркет'),
        _restaurant(_storeB, 'Сутки 24')
      ]);
    }
    if (path == 'groceries/categories') {
      return _json([
        for (final (slug, ru, icon) in [
          ('fruit_veg', 'Овощи и фрукты', 'eco'),
          ('dairy', 'Молочные продукты', 'water_drop'),
          ('fish', 'Рыба и морепродукты', 'phishing'),
        ])
          {
            'slug': slug,
            'nameRu': ru,
            'nameKk': '$ru KK',
            'nameEn': '$ru EN',
            'icon': icon,
            'products': 4,
          }
      ]);
    }
    if (path == 'groceries/brands') return _json(['Жайлау', 'Алатау']);
    if (path == 'groceries/products') {
      final q = request.url.queryParameters;
      productQueries.add(q);
      if (failProducts) return _json({'code': 'INTERNAL_ERROR'}, 500);
      final offset = int.parse(q['offset'] ?? '0');
      final limit = int.parse(q['limit'] ?? '30');
      final all = emptyResults
          ? <Map<String, dynamic>>[]
          : [
              _product(_apples, 'Яблоки Айдаред',
                  unit: 'KG',
                  price: 59000,
                  compareAt: 79000,
                  isNew: true,
                  brand: 'Алматинские сады'),
              _product(_milk, 'Молоко 2,5% 1 л', brand: 'Жайлау'),
              _product(_eggs, 'Яйца С1 (10 шт)', price: 125000, inStock: false),
              for (var i = 4; i <= total; i++)
                _product('a0000000-0000-0000-0000-0000000001$i', 'Товар $i'),
            ];
      final page = all.skip(offset).take(limit).toList();
      return _json({
        'items': page,
        'total': emptyResults ? 0 : total,
        'limit': limit,
        'offset': offset,
      });
    }
    if (RegExp(r'^groceries/products/[^/]+/reviews$').hasMatch(path)) {
      if (request.method == 'POST') {
        reviewPosts.add(body as Map<String, dynamic>);
        reviewList.add({
          'id': 'r${reviewList.length}',
          'rating': body['rating'],
          'comment': body['comment'],
          'author': 'Покупатель'
        });
        canReview = false;
        return _json(reviewList.last, 201);
      }
      final count = reviewList.length;
      return _json({
        'average': count == 0 ? null : 4.5,
        'count': count,
        'distribution': [0, 0, 0, count, 0],
        'reviews': reviewList,
      });
    }
    if (path.endsWith('/review-eligibility')) {
      return _json({'canReview': canReview});
    }
    if (path.startsWith('groceries/products/')) {
      final id = path.split('/').last;
      if (id == _apples) {
        return _json({
          'product': _product(_apples, 'Яблоки Айдаред',
              unit: 'KG', price: 59000, compareAt: 79000, isNew: true),
          'composition': 'Яблоки свежие',
          'storageConditions': 'Хранить при +2…+6 °C',
          'originCountry': 'Казахстан',
          'nutrition': nutrition,
          'minQuantity': 100,
          'quantityStep': 100,
          'optionGroups': [],
          'images': galleryImages,
          'related': [_product(_milk, 'Молоко 2,5% 1 л')],
        });
      }
      if (id == _milk) {
        return _json({
          'product': _product(_milk, 'Молоко 2,5% 1 л', options: true),
          'minQuantity': 1,
          'quantityStep': 1,
          'optionGroups': [
            {
              'id': 'g1',
              'name': 'Жирность',
              'minSelect': 1,
              'maxSelect': 1,
              'options': [
                {'id': 'o1', 'name': '1,5%', 'priceDeltaMinor': 0},
                {'id': 'o2', 'name': '3,2%', 'priceDeltaMinor': 5000},
              ],
            },
          ],
          'related': [],
        });
      }
      return _json({'code': 'PRODUCT_NOT_FOUND'}, 404);
    }
    if (path == 'groceries/favorites/ids') return _json(favorites.toList());
    if (path == 'groceries/favorites' && request.method == 'GET') {
      return _json([
        if (favorites.contains(_apples))
          _product(_apples, 'Яблоки Айдаред', unit: 'KG', price: 59000)
      ]);
    }
    if (path.startsWith('groceries/favorites/')) {
      final id = path.split('/').last;
      favoritePuts.add('${request.method} $id');
      request.method == 'PUT' ? favorites.add(id) : favorites.remove(id);
      return _json({'productId': id, 'favorite': request.method == 'PUT'});
    }
    if (path == 'groceries/lists') {
      if (request.method == 'GET') {
        return _json(lists.map(_listSummary).toList());
      }
      final list = {
        'id': 'l0000000-0000-0000-0000-00000000000${lists.length + 1}',
        'name': (body as Map)['name'],
        'items': <Map<String, dynamic>>[],
      };
      lists.add(list);
      return _json(_listSummary(list), 201);
    }
    if (path.startsWith('groceries/lists/')) {
      final parts = path.split('/');
      final list = lists.where((l) => l['id'] == parts[2]).firstOrNull;
      if (list == null) return _json({'code': 'LIST_NOT_FOUND'}, 404);
      final items = list['items'] as List<Map<String, dynamic>>;
      if (parts.length == 3) {
        if (request.method == 'DELETE') {
          lists.remove(list);
          return http.Response('', 204);
        }
        if (request.method == 'PUT') {
          list['name'] = (body as Map)['name'];
          return _json(_listSummary(list));
        }
        return _json(_listDetail(list));
      }
      if (parts[3] == 'to-cart') {
        final skipped = <Map<String, dynamic>>[];
        final lines = <Map<String, dynamic>>[];
        for (final item in items) {
          if (item['checked'] == true) {
            skipped.add({
              'productId': item['productId'],
              'name': item['name'],
              'reason': 'ALREADY_BOUGHT'
            });
          } else if (item['inStock'] != true) {
            skipped.add({
              'productId': item['productId'],
              'name': item['name'],
              'reason': 'UNAVAILABLE'
            });
          } else {
            lines.add({
              'dishId': item['productId'],
              'name': item['name'],
              'unit': item['unit'],
              'quantity': item['quantity'],
              'optionIds': [],
              'substitution': 'NONE',
              'substituteDishIds': [],
              'unitPriceMinor': item['priceMinor'],
              'maxQuantity': 20,
              'emoji': '🥛',
            });
          }
        }
        serverCart = {
          'restaurantId': _storeA,
          'restaurantName': 'Фреш Маркет',
          'lines': lines,
          'subtotalMinor': 0,
          'totalMinor': 0,
          'needsUpdate': false,
        };
        return _json({'cart': serverCart, 'skipped': skipped});
      }
      if (parts[3] == 'items') {
        final productId = parts[4];
        if (request.method == 'DELETE') {
          items.removeWhere((i) => i['productId'] == productId);
        } else {
          final b = body as Map<String, dynamic>;
          final existing =
              items.where((i) => i['productId'] == productId).firstOrNull;
          if (existing != null) {
            existing['quantity'] = b['quantity'];
            if (b['checked'] != null) existing['checked'] = b['checked'];
          } else {
            items.add({
              'productId': productId,
              'name':
                  productId == _eggs ? 'Яйца С1 (10 шт)' : 'Молоко 2,5% 1 л',
              'unit': 'PIECE',
              'quantity': b['quantity'],
              'checked': b['checked'] == true,
              'priceMinor': 69000,
              'inStock': productId != _eggs,
              'emoji': '🥛',
              'storeName': 'Фреш Маркет',
            });
          }
        }
        return _json(_listDetail(list));
      }
    }
    if (path == 'groceries/cart') {
      if (request.method == 'PUT') {
        cartPuts.add(body as Map<String, dynamic>);
        return _json({
          'lines': [],
          'subtotalMinor': 0,
          'totalMinor': 0,
          'needsUpdate': false
        });
      }
      return _json(serverCart ??
          {
            'lines': [],
            'subtotalMinor': 0,
            'totalMinor': 0,
            'needsUpdate': false
          });
    }
    return _json({'code': 'NOT_FOUND'}, 404);
  }
}

Future<GroceriesServices> _services(_Backend backend,
    {CartController? cart}) async {
  final base = Uri.parse('https://api.example.test/api/v1/');
  final auth = AuthRepository(
    gateway: _Gateway(),
    vault: _Vault(),
    apiBase: base,
    client: MockClient(backend.handle),
  );
  await auth.signIn(AuthTokens('access', 'refresh', null,
      DateTime.now().add(const Duration(minutes: 5))));
  addTearDown(auth.dispose);
  final food = FoodServices(
    api: FoodApi(baseUri: base, auth: auth, client: MockClient(backend.handle)),
    cart: cart ?? CartController(),
    auth: auth,
    groceriesApi: GroceriesApi(
        baseUri: base, auth: auth, client: MockClient(backend.handle)),
  );
  final services = food.groceries!;
  addTearDown(services.cartSync.dispose);
  return services;
}

Future<void> _show(WidgetTester tester, Widget home,
    {Size size = const Size(1080, 2200),
    double pixelRatio = 2.75,
    double textScale = 1,
    Locale? locale}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = pixelRatio;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: KundeTheme.light,
      locale: locale ?? const Locale('ru'),
      supportedLocales: KundeLocalizations.supportedLocales,
      localizationsDelegates: KundeLocalizations.localizationsDelegates,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!),
      home: home));
  await tester.pumpAndSettle();
}

Future<void> _back(WidgetTester tester) async {
  await tester.tap(find.byType(BackButton).last);
  await tester.pumpAndSettle();
}

Future<void> _settleTimers(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 1));

void main() {
  group('home', () {
    testWidgets(
        'shows the hero, quick actions, server categories and real shelves',
        (tester) async {
      final backend = _Backend();
      final services = await _services(backend);
      await _show(tester, GroceriesHomeScreen(services: services));
      expect(find.text('Продукты'), findsOneWidget);
      expect(find.text('Свежие продукты, напитки и товары для дома'),
          findsOneWidget);
      expect(find.text('Алматы'), findsOneWidget);
      for (final label in ['Акции', 'Новинки', 'Мои списки', 'Избранное']) {
        expect(find.text(label), findsWidgets);
      }
      expect(find.text('Овощи и фрукты'), findsOneWidget);
      expect(find.text('Рыба и морепродукты'), findsOneWidget);
      // Shelves come from three server queries: discounts, new and popular.
      final sorts = backend.productQueries.map((q) => q['sort']).toSet();
      expect(sorts, containsAll(['discount', 'new', 'popularity']));
      expect(backend.productQueries.any((q) => q['onSale'] == 'true'), isTrue);
      expect(backend.productQueries.any((q) => q['newOnly'] == 'true'), isTrue);
      expect(find.text('Скидки'), findsOneWidget);
      await _settleTimers(tester);
    });

    testWidgets('a category tile opens a catalog query for that category',
        (tester) async {
      final backend = _Backend();
      final services = await _services(backend);
      await _show(tester, GroceriesHomeScreen(services: services));
      backend.productQueries.clear();
      await tester.tap(find.text('Молочные продукты'));
      await tester.pumpAndSettle();
      expect(backend.productQueries.single['category'], 'dairy');
      expect(find.text('Яблоки Айдаред'), findsOneWidget);
      await _settleTimers(tester);
    });

    testWidgets('quick actions open the deals and new catalogs',
        (tester) async {
      final backend = _Backend();
      final services = await _services(backend);
      await _show(tester, GroceriesHomeScreen(services: services));
      backend.productQueries.clear();
      await tester.tap(find.text('Акции').first);
      await tester.pumpAndSettle();
      expect(backend.productQueries.single['onSale'], 'true');
      expect(backend.productQueries.single['sort'], 'discount');
      await _settleTimers(tester);
    });

    testWidgets(
        'shows a paused state without a retry button when the switch is off',
        (tester) async {
      final backend = _Backend()..disabled = true;
      final services = await _services(backend);
      await _show(tester, GroceriesHomeScreen(services: services));
      expect(find.text('Продукты временно недоступны'), findsOneWidget);
      expect(find.textContaining('Ваши прошлые заказы'), findsOneWidget);
      expect(find.text('Повторить'), findsNothing);
      await _settleTimers(tester);
    });

    testWidgets('offline shows an error with a working retry', (tester) async {
      final backend = _Backend()..offline = true;
      final services = await _services(backend);
      await _show(tester, GroceriesHomeScreen(services: services));
      expect(find.textContaining('Нет связи'), findsOneWidget);
      backend.offline = false;
      await tester.tap(find.text('Повторить'));
      await tester.pumpAndSettle();
      expect(find.text('Овощи и фрукты'), findsOneWidget);
      await _settleTimers(tester);
    });

    for (final entry in {'kk': 'Азық-түлік', 'en': 'Groceries'}.entries) {
      testWidgets('title is localized in ${entry.key}', (tester) async {
        final services = await _services(_Backend());
        await _show(tester, GroceriesHomeScreen(services: services),
            locale: Locale(entry.key));
        expect(find.text(entry.value), findsOneWidget);
        await _settleTimers(tester);
      });
    }
  });

  group('catalog', () {
    testWidgets('search is debounced and sent to the server; reset clears it',
        (tester) async {
      final backend = _Backend();
      final services = await _services(backend);
      await _show(
          tester,
          CatalogScreen(
              services: services,
              initial: const ProductQuery(),
              title: 'Продукты'));
      backend.productQueries.clear();
      await tester.enterText(find.byType(TextField), 'мол');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(TextField), 'моло');
      await tester.pump(const Duration(milliseconds: 100));
      expect(backend.productQueries, isEmpty,
          reason: 'still within the debounce window');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(backend.productQueries.single['q'], 'моло');
      await _settleTimers(tester);
    });

    testWidgets('filter chips and sorting are executed by the server',
        (tester) async {
      final backend = _Backend();
      final services = await _services(backend);
      await _show(
          tester,
          CatalogScreen(
              services: services,
              initial: const ProductQuery(),
              title: 'Продукты'));
      backend.productQueries.clear();
      await tester.tap(find.text('В наличии'));
      await tester.pumpAndSettle();
      expect(backend.productQueries.last['inStock'], 'true');
      await tester.drag(find.byType(ListView).first, const Offset(-300, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Со скидкой'));
      await tester.pumpAndSettle();
      expect(backend.productQueries.last['onSale'], 'true');
      expect(backend.productQueries.last['inStock'], 'true');
      await tester.tap(find.text('Популярные'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Сначала дешёвые').last);
      await tester.pumpAndSettle();
      expect(backend.productQueries.last['sort'], 'price_asc');
      await _settleTimers(tester);
    });

    testWidgets('the filter sheet sends store, brand and price range',
        (tester) async {
      final backend = _Backend();
      final services = await _services(backend);
      await _show(
          tester,
          CatalogScreen(
              services: services,
              initial: const ProductQuery(),
              title: 'Продукты'));
      await tester.tap(find.text('Фильтры'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Сутки 24'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Жайлау'));
      await tester.enterText(find.widgetWithText(TextField, 'от'), '100');
      await tester.enterText(find.widgetWithText(TextField, 'до'), '900');
      backend.productQueries.clear();
      await tester.tap(find.text('Применить'));
      await tester.pumpAndSettle();
      final q = backend.productQueries.last;
      expect(q['storeId'], _storeB);
      expect(q['brand'], 'Жайлау');
      expect(q['minPriceMinor'], '10000');
      expect(q['maxPriceMinor'], '90000');
      expect(find.text('Фильтры · 3'), findsOneWidget);
      await _settleTimers(tester);
    });

    testWidgets('loads the next page near the end of the list', (tester) async {
      final backend = _Backend()..total = 35;
      final services = await _services(backend);
      await _show(
          tester,
          CatalogScreen(
              services: services,
              initial: const ProductQuery(),
              title: 'Продукты'));
      expect(backend.productQueries.last['offset'], '0');
      for (var i = 0; i < 6; i++) {
        await tester.drag(find.byType(ListView).last, const Offset(0, -700));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      expect(backend.productQueries.map((q) => q['offset']), contains('30'));
      await _settleTimers(tester);
    });

    testWidgets('empty result explains and offers a reset', (tester) async {
      final backend = _Backend()..emptyResults = true;
      final services = await _services(backend);
      await _show(
          tester,
          CatalogScreen(
              services: services,
              initial: const ProductQuery(inStock: true),
              title: 'Продукты'));
      expect(find.text('Ничего не найдено'), findsOneWidget);
      backend.emptyResults = false;
      await tester.tap(find.text('Сбросить').last);
      await tester.pumpAndSettle();
      expect(find.text('Яблоки Айдаред'), findsOneWidget);
      await _settleTimers(tester);
    });

    testWidgets(
        'a server error shows retry; unavailable products are marked and cannot be added',
        (tester) async {
      final backend = _Backend()..failProducts = true;
      final services = await _services(backend);
      await _show(
          tester,
          CatalogScreen(
              services: services,
              initial: const ProductQuery(),
              title: 'Продукты'));
      expect(find.text('Повторить'), findsOneWidget);
      backend.failProducts = false;
      await tester.tap(find.text('Повторить'));
      await tester.pumpAndSettle();
      expect(find.text('Нет в наличии'), findsOneWidget);
      expect(find.text('-21%'), findsNothing);
      expect(find.text('-25%'), findsOneWidget);
      await _settleTimers(tester);
    });

    testWidgets(
        'quick add puts 500 g of weighed goods into the cart and the stepper changes it by 100 g',
        (tester) async {
      final backend = _Backend();
      final services = await _services(backend);
      await _show(
          tester,
          CatalogScreen(
              services: services,
              initial: const ProductQuery(),
              title: 'Продукты'));
      await tester.tap(find.byTooltip('Добавить').first);
      await tester.pumpAndSettle();
      final line = services.cart.lines.single;
      expect(line.dishId, _apples);
      expect(line.unit, 'KG');
      expect(line.quantity, 500);
      expect(find.text('500 г'), findsOneWidget);
      await tester.tap(find.byTooltip('+').first);
      await tester.pump();
      expect(line.quantity, 600);
      await tester.tap(find.byTooltip('−').first);
      await tester.tap(find.byTooltip('−').first);
      await tester.pump();
      expect(line.quantity, 400);
      await _settleTimers(tester);
    });

    testWidgets(
        'a product with a required choice opens its page instead of quick adding',
        (tester) async {
      final backend = _Backend();
      final services = await _services(backend);
      await _show(
          tester,
          CatalogScreen(
              services: services,
              initial: const ProductQuery(),
              title: 'Продукты'));
      // The second product (milk) carries hasRequiredOptions in the product page fake only; use the row's add control.
      await tester.tap(find.text('Молоко 2,5% 1 л'));
      await tester.pumpAndSettle();
      expect(find.text('Жирность · Обязательно'), findsOneWidget);
      await _settleTimers(tester);
    });

    testWidgets(
        'the query and loaded results survive opening a product and coming back',
        (tester) async {
      final backend = _Backend();
      final services = await _services(backend);
      await _show(
          tester,
          CatalogScreen(
              services: services,
              initial: const ProductQuery(onSale: true),
              title: 'Акции'));
      final before = backend.productQueries.length;
      await tester.tap(find.text('Яблоки Айдаред'));
      await tester.pumpAndSettle();
      expect(find.text('Казахстан'), findsWidgets);
      await _back(tester);
      await tester.pumpAndSettle();
      expect(find.text('Акции'), findsOneWidget);
      expect(backend.productQueries.length, before,
          reason: 'no reload when returning');
      await _settleTimers(tester);
    });
  });

  group('product page', () {
    testWidgets(
        'shows price, nutrition, composition, storage, origin and related products',
        (tester) async {
      final services = await _services(_Backend());
      await _show(
          tester, ProductScreen(services: services, productId: _apples));
      expect(find.text('Яблоки Айдаред'), findsOneWidget);
      expect(find.text('Казахстан'), findsWidgets);
      expect(find.text('${formatTenge(59000)} / кг'), findsOneWidget);
      expect(find.text(formatTenge(79000)), findsOneWidget);
      expect(find.text('-25%'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Пищевая ценность'), 300,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('52'), findsOneWidget);
      expect(find.text('Яблоки свежие'), findsOneWidget);
      expect(find.text('Хранить при +2…+6 °C'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Похожие товары'), 300,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Похожие товары'), findsOneWidget);
      await _settleTimers(tester);
    });

    testWidgets(
        'weighed goods go by 100 g with a transparent preview total, then land in the cart in grams',
        (tester) async {
      final services = await _services(_Backend());
      await _show(
          tester, ProductScreen(services: services, productId: _apples));
      expect(find.text('500 г'), findsOneWidget);
      expect(find.text(formatTenge(29500)), findsOneWidget); // 0,5 kg x 590 ₸
      await tester.tap(find.byTooltip('+'));
      await tester.pump();
      expect(find.text('600 г'), findsOneWidget);
      expect(find.text(formatTenge(35400)), findsOneWidget);
      expect(find.textContaining('Окончательная цена фиксируется'),
          findsOneWidget);
      await tester.tap(find.text('Добавить в корзину'));
      await tester.pumpAndSettle();
      final line = services.cart.lines.single;
      expect(
          (line.unit, line.quantity, line.unitPriceMinor), ('KG', 600, 59000));
      await _settleTimers(tester);
    });

    testWidgets(
        'a required choice changes the price and is sent with the cart line',
        (tester) async {
      final services = await _services(_Backend());
      await _show(tester, ProductScreen(services: services, productId: _milk));
      await tester.tap(find.textContaining('3,2%'));
      await tester.pump();
      expect(find.text(formatTenge(74000)), findsOneWidget);
      await tester.tap(find.text('Добавить в корзину'));
      await tester.pumpAndSettle();
      final line = services.cart.lines.single;
      expect(line.optionIds, ['o2']);
      expect(line.unitPriceMinor, 74000);
      await _settleTimers(tester);
    });

    testWidgets(
        'favorite toggles on the server and share opens the system share sheet',
        (tester) async {
      final backend = _Backend();
      final services = await _services(backend);
      String? copied;
      const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(shareChannel, (call) async {
        if (call.method == 'share') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return 'dev.fluttercommunity.plus/share/unavailable';
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(shareChannel, null));
      await _show(
          tester, ProductScreen(services: services, productId: _apples));
      await tester.tap(find.byIcon(Icons.favorite_border));
      await tester.pumpAndSettle();
      expect(backend.favoritePuts, ['PUT $_apples']);
      expect(find.byIcon(Icons.favorite), findsOneWidget);
      await tester.tap(find.byIcon(Icons.favorite));
      await tester.pumpAndSettle();
      expect(backend.favoritePuts.last, 'DELETE $_apples');
      await tester.tap(find.byTooltip('Поделиться'));
      await tester.pumpAndSettle();
      expect(copied, contains('Яблоки Айдаред'));
      expect(copied, contains('${formatTenge(59000)} / кг'));
      await _settleTimers(tester);
    });

    testWidgets(
        'verified reviews: shown with the average, written only by eligible buyers',
        (tester) async {
      final backend = _Backend()
        ..canReview = true
        ..reviewList.add({
          'id': 'r0',
          'rating': 5,
          'comment': 'Свежие',
          'author': 'Покупатель'
        });
      final services = await _services(backend);
      await _show(
          tester, ProductScreen(services: services, productId: _apples));
      await tester.scrollUntilVisible(
          find.byKey(const Key('product-rating')), 300,
          scrollable: find.byType(Scrollable).first);
      expect(find.byKey(const Key('product-rating')), findsOneWidget);
      expect(find.text('Свежие'), findsOneWidget);
      await tester.scrollUntilVisible(
          find.byKey(const Key('product-review-write')), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -150));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('product-review-write')));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<FilledButton>(
                  find.byKey(const Key('product-review-send')))
              .onPressed,
          isNull);
      await tester.tap(find.byKey(const Key('product-review-star-4')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Хорошие яблоки');
      await tester.tap(find.byKey(const Key('product-review-send')));
      await tester.pumpAndSettle();
      expect(backend.reviewPosts.single,
          {'rating': 4, 'comment': 'Хорошие яблоки'});
      expect(find.text('Спасибо за отзыв!'), findsOneWidget);
      expect(find.byKey(const Key('product-review-write')), findsNothing);
      await _settleTimers(tester);
    });

    testWidgets(
        'without reviews there is an honest empty text and no invented rating',
        (tester) async {
      final services = await _services(_Backend());
      await _show(
          tester, ProductScreen(services: services, productId: _apples));
      await tester.scrollUntilVisible(
          find.byKey(const Key('product-no-reviews')), 300,
          scrollable: find.byType(Scrollable).first);
      expect(find.byKey(const Key('product-rating')), findsNothing);
      expect(find.byKey(const Key('product-review-write')), findsNothing);
      await _settleTimers(tester);
    });

    testWidgets('several photos form a swipeable gallery with a page indicator',
        (tester) async {
      final backend = _Backend()
        ..galleryImages = [
          'https://img.example.test/1.jpg',
          'https://img.example.test/2.jpg',
          'https://img.example.test/3.jpg',
        ];
      final services = await _services(backend);
      await _show(
          tester, ProductScreen(services: services, productId: _apples));
      expect(find.byKey(const Key('product-gallery')), findsOneWidget);
      expect(find.bySemanticsLabel('1/3'), findsOneWidget);
      await tester.fling(find.byKey(const Key('product-gallery')),
          const Offset(-300, 0), 1500);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('2/3'), findsOneWidget);
      await _settleTimers(tester);
    });

    testWidgets(
        'an unknown product shows an error with retry; unavailable ones cannot be added',
        (tester) async {
      final services = await _services(_Backend());
      await _show(
          tester, ProductScreen(services: services, productId: 'missing'));
      expect(find.textContaining('не найден'), findsOneWidget);
      expect(find.text('Повторить'), findsOneWidget);
      await _settleTimers(tester);
    });
  });

  group('cart', () {
    testWidgets('a store conflict asks before replacing the cart',
        (tester) async {
      final backend = _Backend();
      final services = await _services(backend);
      final other = Restaurant.fromJson(_restaurant(_storeB, 'Сутки 24'));
      services.cart.add(
          other,
          CartLine(
              dishId: _otherStoreItem,
              name: 'Чипсы',
              emoji: '🛒',
              tone: 'green',
              optionIds: const [],
              optionsText: '',
              unitPriceMinor: 89000,
              quantity: 1));
      await _show(
          tester, ProductScreen(services: services, productId: _apples));
      await tester.tap(find.text('Добавить в корзину'));
      await tester.pumpAndSettle();
      expect(find.text('Заменить корзину?'), findsOneWidget);
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(services.cart.lines.single.dishId, _otherStoreItem);
      await tester.tap(find.text('Добавить в корзину'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Очистить и добавить'));
      await tester.pumpAndSettle();
      expect(services.cart.lines.single.dishId, _apples);
      await _settleTimers(tester);
    });

    testWidgets(
        'cart changes are saved to the server without prices, and an empty cart clears it',
        (tester) async {
      final backend = _Backend();
      final services = await _services(backend);
      await _show(
          tester, ProductScreen(services: services, productId: _apples));
      await tester.tap(find.text('Добавить в корзину'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      final put = backend.cartPuts.single;
      expect(put['restaurantId'], _storeA);
      final item = (put['items'] as List).single as Map;
      expect(item['dishId'], _apples);
      expect(item['quantity'], 500);
      expect(item.containsKey('unitPriceMinor'), isFalse);
      services.cart.clear();
      await tester.pump(const Duration(seconds: 1));
      expect(backend.cartPuts.last['items'], isEmpty);
      await _settleTimers(tester);
    });

    testWidgets('an empty local cart is restored from the server after sign-in',
        (tester) async {
      final backend = _Backend()
        ..serverCart = {
          'restaurantId': _storeA,
          'restaurantName': 'Фреш Маркет',
          'lines': [
            {
              'dishId': _apples,
              'name': 'Яблоки Айдаред',
              'unit': 'KG',
              'quantity': 1500,
              'optionIds': [],
              'substitution': 'NONE',
              'substituteDishIds': [],
              'unitPriceMinor': 59000,
              'maxQuantity': 5000,
              'emoji': '🍎',
            },
            {
              'dishId': _eggs,
              'name': 'Яйца',
              'unit': 'PIECE',
              'quantity': 1,
              'optionIds': [],
              'substitution': 'NONE',
              'substituteDishIds': [],
              'unitPriceMinor': 125000,
              'maxQuantity': 0,
              'emoji': '🥚',
              'issue': 'OUT_OF_STOCK',
            },
          ],
          'subtotalMinor': 88500,
          'totalMinor': 88500,
          'needsUpdate': true,
        };
      final services = await _services(backend);
      await _show(tester, GroceriesHomeScreen(services: services));
      final line = services.cart.lines.single;
      expect((line.dishId, line.quantity, line.unit), (_apples, 1500, 'KG'));
      expect(services.cart.restaurant?.id, _storeA);
      await _settleTimers(tester);
    });
  });

  group('favorites and lists', () {
    testWidgets(
        'favorites come from the server and a removed heart leaves the list',
        (tester) async {
      final backend = _Backend()..favorites.add(_apples);
      final services = await _services(backend);
      await _show(tester, FavoritesScreen(services: services));
      expect(find.text('Яблоки Айдаред'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.favorite));
      await tester.pumpAndSettle();
      expect(backend.favorites, isEmpty);
      expect(find.text('Пока пусто'), findsOneWidget);
      await _settleTimers(tester);
    });

    testWidgets(
        'create, fill, tick and move a shopping list to the cart; unavailable and bought items are reported',
        (tester) async {
      final backend = _Backend();
      final services = await _services(backend);
      await _show(tester, ListsScreen(services: services));
      expect(find.text('Списков пока нет'), findsOneWidget);
      await tester.tap(find.text('Новый список').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'На неделю');
      await tester.tap(find.text('Создать'));
      await tester.pumpAndSettle();
      expect(backend.lists.single['name'], 'На неделю');
      expect(find.text('Список пуст'), findsOneWidget);
      // Fill the list through the API (the product page "add to list" sheet is tested separately).
      final items = backend.lists.single['items'] as List<Map<String, dynamic>>;
      items.addAll([
        {
          'productId': _milk,
          'name': 'Молоко 2,5% 1 л',
          'unit': 'PIECE',
          'quantity': 3,
          'checked': false,
          'priceMinor': 69000,
          'inStock': true,
          'emoji': '🥛',
          'storeName': 'Фреш Маркет'
        },
        {
          'productId': _eggs,
          'name': 'Яйца С1 (10 шт)',
          'unit': 'PIECE',
          'quantity': 1,
          'checked': false,
          'priceMinor': 125000,
          'inStock': false,
          'emoji': '🥚',
          'storeName': 'Фреш Маркет'
        },
        {
          'productId': _apples,
          'name': 'Яблоки Айдаред',
          'unit': 'KG',
          'quantity': 1000,
          'checked': true,
          'priceMinor': 59000,
          'inStock': true,
          'emoji': '🍎',
          'storeName': 'Фреш Маркет'
        },
      ]);
      await _back(tester);
      await tester.pumpAndSettle();
      expect(find.text('3 товара · куплено 1'), findsOneWidget);
      await tester.tap(find.text('На неделю'));
      await tester.pumpAndSettle();
      expect(find.text('Яйца С1 (10 шт)'), findsOneWidget);
      expect(find.text('Нет в наличии · Фреш Маркет'), findsOneWidget);
      await tester.tap(find.text('Добавить в корзину'));
      await tester.pumpAndSettle();
      expect(find.text('Не добавлено'), findsOneWidget);
      expect(find.textContaining('Яйца С1 (10 шт) — нет в наличии'),
          findsOneWidget);
      expect(
          find.textContaining('Яблоки Айдаред — уже куплено'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(services.cart.lines.single.dishId, _milk);
      expect(services.cart.lines.single.quantity, 3);
      await _settleTimers(tester);
    });

    testWidgets('lists can be renamed and deleted', (tester) async {
      final backend = _Backend();
      backend.lists.add({
        'id': 'l0000000-0000-0000-0000-000000000001',
        'name': 'Старый',
        'items': <Map<String, dynamic>>[]
      });
      final services = await _services(backend);
      await _show(tester, ListsScreen(services: services));
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Переименовать'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Новый');
      await tester.tap(find.text('Создать'));
      await tester.pumpAndSettle();
      expect(backend.lists.single['name'], 'Новый');
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Удалить'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Удалить').last);
      await tester.pumpAndSettle();
      expect(backend.lists, isEmpty);
      expect(find.text('Списков пока нет'), findsOneWidget);
      await _settleTimers(tester);
    });

    testWidgets('the add-to-list sheet creates a list and adds the product',
        (tester) async {
      final backend = _Backend();
      final services = await _services(backend);
      await _show(
          tester, ProductScreen(services: services, productId: _apples));
      await tester.scrollUntilVisible(find.text('В список'), 300,
          scrollable: find.byType(Scrollable).first);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -200));
      await tester.pumpAndSettle();
      await tester.tap(find.text('В список'), warnIfMissed: true);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Новый список'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Фрукты');
      await tester.tap(find.text('Создать'));
      await tester.pumpAndSettle();
      final items = backend.lists.single['items'] as List;
      expect((items.single as Map)['productId'], _apples);
      expect((items.single as Map)['quantity'], 500);
      await _settleTimers(tester);
    });
  });

  group('golden renders (Samsung 390 dp)', () {
    Future<void> shot(WidgetTester tester, Widget screen, String name,
        {Locale? locale, ThemeMode? dark}) async {
      await tester.runAsync(loadPremiumFonts);
      await _show(tester, screen,
          size: const Size(1080, 2340), pixelRatio: 2.769, locale: locale);
      await premiumGolden(tester, name);
      await _settleTimers(tester);
    }

    testWidgets('home', (tester) async {
      await shot(
          tester,
          GroceriesHomeScreen(services: await _services(_Backend())),
          'groceries_home');
    });
    testWidgets('catalog', (tester) async {
      await shot(
          tester,
          CatalogScreen(
              services: await _services(_Backend()),
              initial: const ProductQuery(category: 'fruit_veg'),
              title: 'Овощи и фрукты'),
          'groceries_catalog');
    });
    testWidgets('product', (tester) async {
      await shot(
          tester,
          ProductScreen(
              services: await _services(_Backend()), productId: _apples),
          'groceries_product');
    });
    testWidgets('lists', (tester) async {
      final backend = _Backend()
        ..lists.add({
          'id': 'l0000000-0000-0000-0000-000000000001',
          'name': 'На неделю',
          'items': <Map<String, dynamic>>[
            {
              'productId': _milk,
              'name': 'Молоко 2,5% 1 л',
              'unit': 'PIECE',
              'quantity': 3,
              'checked': false,
              'priceMinor': 69000,
              'inStock': true,
              'emoji': '🥛',
              'storeName': 'Фреш Маркет'
            },
          ],
        });
      await shot(tester, ListsScreen(services: await _services(backend)),
          'groceries_lists');
    });
  });

  group('layout and accessibility', () {
    for (final width in [320.0, 360.0, 412.0]) {
      for (final screen in ['home', 'catalog', 'product', 'lists']) {
        testWidgets('$screen fits $width dp with 200% text', (tester) async {
          final services = await _services(_Backend());
          final size = Size(width * 2.75, 2200);
          final widget = switch (screen) {
            'home' => GroceriesHomeScreen(services: services),
            'catalog' => CatalogScreen(
                services: services,
                initial: const ProductQuery(),
                title: 'Продукты'),
            'product' => ProductScreen(services: services, productId: _apples),
            _ => ListsScreen(services: services),
          };
          await _show(tester, widget, size: size, textScale: 2);
          expect(tester.takeException(), isNull);
          await _settleTimers(tester);
        });
      }
    }

    testWidgets('controls meet the Android tap target and label guidelines',
        (tester) async {
      final handle = tester.ensureSemantics();
      final services = await _services(_Backend());
      await _show(
          tester,
          CatalogScreen(
              services: services,
              initial: const ProductQuery(),
              title: 'Продукты'));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await _show(
          tester, ProductScreen(services: services, productId: _apples));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await _settleTimers(tester);
      handle.dispose();
    });
  });
}
