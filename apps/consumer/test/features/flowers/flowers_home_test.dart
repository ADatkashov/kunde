import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_mobile/features/flowers/presentation/flowers_home_screen.dart';
import 'package:kunde_mobile/features/home/data/kunde_api.dart';
import 'package:kunde_mobile/features/home/data/platform_snapshot.dart';

Map<String, dynamic> _shop(String id, String name) => {
      'id': id,
      'slug': id,
      'name': name,
      'description': 'Вымышленный магазин',
      'emoji': '💐',
      'tone': 'red',
      'imageUrl': null,
      'deliveryFeeMinor': 100000,
      'minOrderMinor': 0,
      'etaMinMinutes': 30,
      'etaMaxMinutes': 45,
      'open': true,
      'synthetic': true,
      'productCount': 2,
    };

Map<String, dynamic> _product(String id, String name, int price) => {
      'id': id,
      'shopId': 's1',
      'shopName': 'Лавка',
      'categoryCode': 'BOUQUETS',
      'name': name,
      'description': '',
      'priceMinor': price,
      'emoji': '🌹',
      'tone': 'red',
      'imageUrl': null,
      'available': true,
      'stockQty': null,
      'popular': true,
    };

class _Backend {
  final requested = <Uri>[];

  Future<http.Response> handle(http.Request r) async {
    requested.add(r.url);
    Object body;
    switch (r.url.path) {
      case '/api/v1/flowers/categories':
        body = [
          for (final (code, name) in [
            ('BOUQUETS', 'Букеты'),
            ('GIFTS', 'Подарки')
          ])
            {
              'code': code,
              'nameRu': name,
              'nameKk': name,
              'nameEn': name,
              'icon': 'local_florist',
              'featured': true,
            },
        ];
      case '/api/v1/flowers/products/popular':
        body = [_product('p1', 'Букет «Классика»', 1790000)];
      case '/api/v1/flowers/shops':
        body = r.url.queryParameters['category'] == 'GIFTS'
            ? [_shop('s2', 'Дом подарков')]
            : [_shop('s1', 'Цветочная лавка'), _shop('s2', 'Дом подарков')];
      default:
        return http.Response('{}', 404);
    }
    return http.Response(jsonEncode(body), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});
  }
}

void main() {
  test('the platform snapshot reads flowersEnabled and defaults to off', () {
    PlatformSnapshot parse(Map<String, dynamic> extra) =>
        PlatformSnapshot.fromJson({
          'releaseStage': 'DEV',
          'marketplaceEnabled': true,
          'oidcIssuerConfigured': false,
          'aiEnabled': false,
          ...extra,
        });
    expect(parse({}).flowersEnabled, isFalse);
    expect(parse({'flowersEnabled': true}).flowersEnabled, isTrue);
  });

  testWidgets(
      'home shows categories, popular products and shops and filters by category',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final backend = _Backend();
    final api = KundeApi(
        baseUri: Uri.parse('https://api.example.test/api/v1/'),
        client: MockClient(backend.handle));
    addTearDown(api.close);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: const [Locale('en')],
      home: FlowersHomeScreen(api: api),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Flowers & gifts'), findsOneWidget);
    expect(find.byKey(const ValueKey('category-BOUQUETS')), findsOneWidget);
    expect(find.text('Popular'), findsOneWidget);
    expect(find.text('Букет «Классика»'), findsOneWidget);
    expect(find.text('17 900 ₸'), findsOneWidget);
    expect(find.text('Цветочная лавка'), findsOneWidget);
    expect(find.text('Found: 2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('category-GIFTS')));
    await tester.pumpAndSettle();
    expect(backend.requested.last.queryParameters['category'], 'GIFTS');
    expect(find.text('Цветочная лавка'), findsNothing);
    expect(find.text('Found: 1'), findsOneWidget);
    // the popular showcase only belongs to the unfiltered home
    expect(find.text('Popular'), findsNothing);
  });

  testWidgets('a failed shop list offers a retry', (tester) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    var fail = true;
    final api = KundeApi(
        baseUri: Uri.parse('https://api.example.test/api/v1/'),
        client: MockClient((r) async {
          if (r.url.path.endsWith('/shops') && fail) {
            return http.Response('x', 503);
          }
          return _Backend().handle(r);
        }));
    addTearDown(api.close);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: const [Locale('en')],
      home: FlowersHomeScreen(api: api),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Цветочная лавка'), findsOneWidget);
  });
}
