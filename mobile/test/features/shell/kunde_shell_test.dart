import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_mobile/core/localization/kunde_localizations.dart';
import 'package:kunde_mobile/features/home/data/kunde_api.dart';
import 'package:kunde_mobile/features/home/presentation/catalog_search_panel.dart';
import 'package:kunde_mobile/features/shell/kunde_shell.dart';
import 'package:kunde_mobile/shared/theme/kunde_theme.dart';

KundeApi _api({bool marketplace = false}) => KundeApi(
    baseUri: Uri.parse('https://api.example.test/api/v1/'),
    client: MockClient((_) async => http.Response(
        jsonEncode({
          'releaseStage': 'FOUNDATION',
          'marketplaceEnabled': marketplace,
          'oidcIssuerConfigured': false,
          'aiEnabled': false,
        }),
        200)));

Future<void> _pump(WidgetTester tester, KundeApi api,
    {String locale = 'ru',
    Size size = const Size(390, 844),
    double textScale = 1}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: KundeTheme.light,
    localizationsDelegates: KundeLocalizations.localizationsDelegates,
    supportedLocales: KundeLocalizations.supportedLocales,
    locale: Locale(locale),
    builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale), disableAnimations: true),
        child: child!),
    home: KundeShell(api: api),
  ));
  await tester.pumpAndSettle();
}

void main() {
  final bar = find.byType(NavigationBar);
  Finder inBar(String label) =>
      find.descendant(of: bar, matching: find.text(label));

  testWidgets('bottom bar has exactly the four approved tabs', (tester) async {
    await _pump(tester, _api());
    expect(tester.widget<NavigationBar>(bar).destinations.length, 4);
    for (final label in ['Главная', 'Поиск', 'Заказы', 'Профиль']) {
      expect(inBar(label), findsOneWidget);
    }
  });

  testWidgets('labels are localized in Kazakh and English', (tester) async {
    await _pump(tester, _api(), locale: 'kk');
    for (final label in ['Басты бет', 'Іздеу', 'Тапсырыстар', 'Профиль']) {
      expect(inBar(label), findsOneWidget);
    }
    await _pump(tester, _api(), locale: 'en');
    for (final label in ['Home', 'Search', 'Orders', 'Profile']) {
      expect(inBar(label), findsOneWidget);
    }
  });

  testWidgets('search tab explains unavailability while marketplace is off',
      (tester) async {
    await _pump(tester, _api());
    await tester.tap(inBar('Поиск'));
    await tester.pumpAndSettle();
    expect(find.text('Поиск пока недоступен'), findsOneWidget);
    expect(find.byType(CatalogSearchPanel), findsNothing);
  });

  testWidgets('search tab shows real catalog search when enabled',
      (tester) async {
    await _pump(tester, _api(marketplace: true));
    await tester.tap(inBar('Поиск'));
    await tester.pumpAndSettle();
    expect(find.byType(CatalogSearchPanel), findsOneWidget);
  });

  testWidgets('orders tab is an honest empty state', (tester) async {
    await _pump(tester, _api());
    await tester.tap(inBar('Заказы'));
    await tester.pumpAndSettle();
    expect(find.text('Заказов пока нет'), findsOneWidget);
    expect(find.textContaining('оформить заказ нельзя'), findsOneWidget);
  });

  testWidgets('profile tab says sign-in is not set up', (tester) async {
    await _pump(tester, _api());
    await tester.tap(inBar('Профиль'));
    await tester.pumpAndSettle();
    expect(find.text('Вход пока не настроен'), findsOneWidget);
  });

  testWidgets('home links open the Orders and Search tabs', (tester) async {
    await _pump(tester, _api(marketplace: true), size: const Size(390, 2400));
    await tester.tap(find.text('Мои заказы'));
    await tester.pumpAndSettle();
    expect(find.text('Заказов пока нет'), findsOneWidget);
    await tester.tap(inBar('Главная'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Что хотите сделать сегодня?'));
    await tester.pumpAndSettle();
    expect(find.byType(CatalogSearchPanel), findsOneWidget);
  });

  testWidgets('destinations keep 48 px touch targets and semantics',
      (tester) async {
    await _pump(tester, _api());
    for (var i = 0; i < 4; i++) {
      final size = tester.getSize(find
          .descendant(of: bar, matching: find.byType(NavigationDestination))
          .at(i));
      expect(size.height >= 48 && size.width >= 48, isTrue,
          reason: 'tab $i target is $size');
    }
    expect(find.bySemanticsLabel('Основная навигация'), findsOneWidget);
  });

  for (final locale in ['ru', 'kk', 'en']) {
    for (final size in [const Size(320, 640), const Size(390, 844)]) {
      testWidgets('no overflow in every tab $locale ${size.width}',
          (tester) async {
        await _pump(tester, _api(), locale: locale, size: size, textScale: 2);
        for (final i in [0, 1, 2, 3]) {
          await tester.tap(find.descendant(
              of: bar, matching: find.byType(NavigationDestination).at(i)));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'tab $i');
        }
      });
    }
  }
}
