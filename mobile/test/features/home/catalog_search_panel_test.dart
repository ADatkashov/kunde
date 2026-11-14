import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_mobile/core/localization/kunde_formats.dart';
import 'package:kunde_mobile/core/localization/kunde_localizations.dart';
import 'package:kunde_mobile/features/home/data/kunde_api.dart';
import 'package:kunde_mobile/features/home/presentation/catalog_search_panel.dart';
import 'package:kunde_mobile/features/home/presentation/home_screen.dart';
import 'package:kunde_mobile/shared/theme/kunde_theme.dart';

Widget _app(Widget home, {String locale = 'ru'}) => MaterialApp(
      theme: KundeTheme.light,
      localizationsDelegates: KundeLocalizations.localizationsDelegates,
      supportedLocales: KundeLocalizations.supportedLocales,
      locale: Locale(locale),
      home: Scaffold(body: home),
    );

KundeApi _api(MockClientHandler handler) => KundeApi(
    baseUri: Uri.parse('https://api.example.test/api/v1/'),
    client: MockClient(handler));

const _json = {'content-type': 'application/json; charset=utf-8'};

/// Routes by path: categories on /search, offerings on /search/offerings.
MockClientHandler _catalog(
        {List<Map<String, dynamic>> categories = const [],
        List<Map<String, dynamic>> offerings = const []}) =>
    (request) async => http.Response(
        jsonEncode(request.url.path.endsWith('/search/offerings')
            ? offerings
            : categories),
        200,
        headers: _json);

Map<String, dynamic> _offering(String name, {String? en, String? partner, int? price, bool? available}) => {
      'id': 'o-$name',
      'categoryId': 'c',
      'kind': 'SERVICE',
      'nameRu': name,
      'nameKk': '$name-kk',
      if (en != null) 'nameEn': en,
      if (partner != null) 'partnerName': partner,
      if (price != null) 'priceMinor': price,
      if (price != null) 'currency': 'KZT',
      if (available != null) 'available': available,
    };

void main() {
  testWidgets('shows server results in the active language', (tester) async {
    String? requestedQuery;
    final inner = _catalog(categories: [
      {'id': 'a', 'nameRu': 'Уборка', 'nameKk': 'Тазалау'}
    ]);
    final api = _api((request) async {
      requestedQuery = request.url.queryParameters['q'];
      return inner(request);
    });
    await tester.pumpWidget(_app(CatalogSearchPanel(api: api), locale: 'kk'));

    await tester.enterText(find.byType(TextField), '  таз ');
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    expect(requestedQuery, 'таз');
    expect(find.text('Тазалау'), findsOneWidget);
    expect(find.text('Уборка'), findsNothing);
    api.close();
  });

  testWidgets('shows the approved partner name under an offering',
      (tester) async {
    final api = _api(_catalog(offerings: [
      _offering('Чистка', partner: 'Синтетический партнёр'),
      _offering('Без партнёра'),
    ]));
    await tester.pumpWidget(_app(CatalogSearchPanel(api: api)));

    await tester.enterText(find.byType(TextField), 'чист');
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    expect(find.text('Чистка'), findsOneWidget);
    expect(find.text('Синтетический партнёр'), findsOneWidget);
    expect(find.text('Без партнёра'), findsOneWidget);
    api.close();
  });

  testWidgets('shows the KZT price and an explicit unavailable marker',
      (tester) async {
    final api = _api(_catalog(offerings: [
      _offering('Чистка', partner: 'Партнёр', price: 250050, available: true),
      _offering('Стирка', price: 100000, available: false),
    ]));
    await tester.pumpWidget(_app(CatalogSearchPanel(api: api)));

    await tester.enterText(find.byType(TextField), 'чист');
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    final price = KundeFormats.money(250050, 'KZT', const Locale('ru'));
    expect(find.text('Партнёр · $price'), findsOneWidget);
    expect(find.textContaining('Сейчас недоступно'), findsOneWidget);
    api.close();
  });

  testWidgets('shows an honest empty state and never demo categories',
      (tester) async {
    final api = _api(_catalog());
    await tester.pumpWidget(_app(CatalogSearchPanel(api: api)));

    await tester.enterText(find.byType(TextField), 'еда');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('Ничего не найдено. Попробуйте другой запрос.'),
        findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
    api.close();
  });

  testWidgets('blank query sends no request', (tester) async {
    var calls = 0;
    final api = _api((_) async {
      calls++;
      return http.Response('[]', 200);
    });
    await tester.pumpWidget(_app(CatalogSearchPanel(api: api)));

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    expect(calls, 0);
    api.close();
  });

  testWidgets('failure shows a safe message and retry recovers',
      (tester) async {
    var fail = true;
    final ok = _catalog(categories: [
      {'id': 'a', 'nameRu': 'Уборка', 'nameKk': 'Тазалау'}
    ]);
    final api = _api((request) async =>
        fail ? http.Response('internal db host', 500) : ok(request));
    await tester.pumpWidget(_app(CatalogSearchPanel(api: api), locale: 'en'));

    await tester.enterText(find.byType(TextField), 'clean');
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    expect(find.text('Search failed. Please try again.'), findsOneWidget);
    expect(find.textContaining('internal'), findsNothing);

    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Уборка'), findsOneWidget);
    api.close();
  });

  testWidgets('malformed response is treated as failure', (tester) async {
    final api = _api((_) async => http.Response('{"x":1}', 200));
    await tester.pumpWidget(_app(CatalogSearchPanel(api: api)));

    await tester.enterText(find.byType(TextField), 'еда');
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    expect(find.text('Не удалось выполнить поиск. Попробуйте ещё раз.'),
        findsOneWidget);
    api.close();
  });

  testWidgets('shows published offerings with language fallback',
      (tester) async {
    final api = _api(_catalog(offerings: [
      _offering('Генеральная уборка', en: 'Deep cleaning'),
      _offering('Мытьё окон'),
    ]));
    await tester.pumpWidget(_app(CatalogSearchPanel(api: api), locale: 'en'));

    await tester.enterText(find.byType(TextField), 'clean');
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    expect(find.text('Deep cleaning'), findsOneWidget);
    expect(find.text('Мытьё окон'), findsOneWidget);
    expect(find.text('Search failed. Please try again.'), findsNothing);
    api.close();
  });

  testWidgets('offerings use the Kazakh name in Kazakh', (tester) async {
    final api = _api(_catalog(offerings: [_offering('Уборка')]));
    await tester.pumpWidget(_app(CatalogSearchPanel(api: api), locale: 'kk'));

    await tester.enterText(find.byType(TextField), 'уб');
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    expect(find.text('Уборка-kk'), findsOneWidget);
    api.close();
  });

  testWidgets('a failed offerings lookup is a failure, not a partial answer',
      (tester) async {
    final api = _api((request) async => request.url.path.endsWith('/offerings')
        ? http.Response('boom', 503)
        : http.Response(
            jsonEncode([
              {'id': 'a', 'nameRu': 'Уборка', 'nameKk': 'Тазалау'}
            ]),
            200,
            headers: _json));
    await tester.pumpWidget(_app(CatalogSearchPanel(api: api), locale: 'en'));

    await tester.enterText(find.byType(TextField), 'clean');
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    expect(find.text('Search failed. Please try again.'), findsOneWidget);
    expect(find.text('Уборка'), findsNothing);
    api.close();
  });

  testWidgets('malformed offering is treated as failure', (tester) async {
    final api = _api(_catalog(offerings: [
      {'id': 'x'}
    ]));
    await tester.pumpWidget(_app(CatalogSearchPanel(api: api), locale: 'en'));

    await tester.enterText(find.byType(TextField), 'x');
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    expect(find.text('Search failed. Please try again.'), findsOneWidget);
    api.close();
  });

  testWidgets('home shows search only when the marketplace is enabled',
      (tester) async {
    Future<void> pumpHome(bool enabled) async {
      final api = _api((_) async => http.Response(
          jsonEncode({
            'releaseStage': 'FOUNDATION',
            'marketplaceEnabled': enabled,
            'oidcIssuerConfigured': false,
            'aiEnabled': false,
          }),
          200));
      await tester
          .pumpWidget(_app(HomeScreen(key: ValueKey(enabled), api: api)));
      await tester.pumpAndSettle();
    }

    await pumpHome(false);
    await tester.tap(find.text('Что хотите сделать сегодня?'));
    await tester.pumpAndSettle();
    expect(find.byType(CatalogSearchPanel), findsNothing);
    expect(find.text('Поиск заработает, когда сервисы будут запущены.'),
        findsOneWidget);
    await tester.tap(find.text('Закрыть'));
    await tester.pumpAndSettle();
    await pumpHome(true);
    await tester.tap(find.text('Что хотите сделать сегодня?'));
    await tester.pumpAndSettle();
    expect(find.byType(CatalogSearchPanel), findsOneWidget);
  });
}
