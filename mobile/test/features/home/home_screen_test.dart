import 'dart:convert';
import '../../support/premium_goldens.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_mobile/core/localization/kunde_localizations.dart';
import 'package:kunde_mobile/features/home/data/kunde_api.dart';
import 'package:kunde_mobile/features/home/presentation/home_screen.dart';
import 'package:kunde_mobile/features/home/presentation/super_app_widgets.dart';
import 'package:kunde_mobile/shared/theme/kunde_theme.dart';

KundeApi _api({bool marketplace = false, bool fail = false}) => KundeApi(
    baseUri: Uri.parse('https://api.example.test/api/v1/'),
    client: MockClient((_) async => fail
        ? http.Response('x', 500)
        : http.Response(
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
    double textScale = 1,
    ThemeData? theme}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme ?? KundeTheme.light,
    localizationsDelegates: KundeLocalizations.localizationsDelegates,
    supportedLocales: KundeLocalizations.supportedLocales,
    locale: Locale(locale),
    builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale), disableAnimations: true),
        child: child!),
    home: HomeScreen(api: api),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('promo brand names stay on one line at 320 dp', (tester) async {
    await tester.runAsync(loadPremiumFonts);
    await _pump(tester, _api(), size: const Size(320, 640), locale: 'kk');
    for (final brand in ['KUNDE AI', 'KUNDE+']) {
      final label = find.descendant(
        of: find.byType(HomePromoCard),
        matching: find.text(brand),
      );
      final paragraph = tester.renderObject<RenderParagraph>(label);
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: brand.length),
      );
      expect(boxes.map((box) => box.top).toSet(), hasLength(1), reason: brand);
    }
  });

  for (final width in [360.0, 390.0, 412.0]) {
    testWidgets('premium golden home Samsung $width', (tester) async {
      await tester.runAsync(loadPremiumFonts);
      await _pump(tester, _api(marketplace: true), size: Size(width, 1200));
      await premiumGolden(tester, 'premium_home_${width.toInt()}');
    });
  }

  testWidgets('shows Super App layout with honest unavailable states',
      (tester) async {
    await _pump(tester, _api(), size: const Size(390, 2400));

    expect(find.text('Алматы'), findsWidgets);
    expect(find.text('Найти сервис, услугу или товар'), findsOneWidget);
    expect(find.text('Еда'), findsOneWidget);
    expect(find.text('Продукты'), findsOneWidget);
    expect(find.text('Рядом с вами'), findsOneWidget);
    // Every category is "soon" while the marketplace is disabled.
    expect(find.text('Скоро'), findsWidgets);
    expect(find.text('Пока нет ресторанов'), findsOneWidget);
    expect(find.text('Сервисы пока не запущены'), findsOneWidget);
    expect(find.text('Сервер доступен'), findsOneWidget);
    expect(find.text('KUNDE AI'), findsOneWidget);
    // No invented restaurants, ratings or delivery times.
    expect(find.text('BurgerHouse'), findsNothing);
    expect(find.textContaining('мин'), findsNothing);
    expect(find.text('Еда и покупки'), findsNothing);
  });

  testWidgets('opens Education only when enabled by the backend',
      (tester) async {
    final requests = <String>[];
    final api = KundeApi(
      baseUri: Uri.parse('https://api.example.test/api/v1/'),
      client: MockClient((request) async {
        requests.add(request.url.path);
        return http.Response(
          jsonEncode(request.url.path.endsWith('/capabilities')
              ? {
                  'releaseStage': 'FOUNDATION',
                  'marketplaceEnabled': false,
                  'oidcIssuerConfigured': false,
                  'aiEnabled': false,
                  'educationEnabled': true,
                }
              : {'items': [], 'hasMore': false}),
          200,
        );
      }),
    );
    addTearDown(api.close);
    final disabled = _api();
    addTearDown(disabled.close);
    await _pump(tester, disabled, locale: 'kk');
    expect(find.text('Білім'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(tester, api,
        locale: 'kk',
        size: const Size(390, 1800),
        textScale: 2,
        theme: KundeTheme.dark);
    final tile = find.text('Білім');
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.text('Білім және курстар'), findsWidgets);
    expect(requests, contains('/api/v1/education/courses'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens the unavailable assistant and returns by Back',
      (tester) async {
    await _pump(tester, _api());
    await tester.tap(find.text('KUNDE AI'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('inactive category opens info sheet and offers no order',
      (tester) async {
    await _pump(tester, _api());
    await tester.tap(find.text('Авто'));
    await tester.pumpAndSettle();
    expect(find.text('Скоро в KUNDE'), findsOneWidget);
    expect(find.text('Закрыть'), findsOneWidget);
    await tester.tap(find.text('Закрыть'));
    await tester.pumpAndSettle();
    expect(find.text('Скоро в KUNDE'), findsNothing);
  });

  testWidgets('secondary categories remain reachable from All services',
      (tester) async {
    await _pump(tester, _api());
    await tester.tap(find.text('Все сервисы'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Поездки'));
    await tester.pumpAndSettle();
    expect(find.text('Скоро в KUNDE'), findsOneWidget);
  });

  testWidgets('food category opens search only when marketplace is enabled',
      (tester) async {
    await _pump(tester, _api(marketplace: true));
    expect(find.text('Доступно'), findsNothing); // semantic only
    await tester.tap(find.text('Еда'));
    await tester.pumpAndSettle();
    expect(find.text('Поиск по категориям'), findsWidgets);
  });

  testWidgets('offline shows retry and keeps categories disabled',
      (tester) async {
    await _pump(tester, _api(fail: true));
    expect(find.text('Не удалось связаться с сервером'), findsWidgets);
    expect(find.text('Повторить'), findsOneWidget);
    expect(find.text('Продукты'), findsOneWidget);
  });

  for (final locale in ['ru', 'kk', 'en']) {
    for (final size in [const Size(320, 640), const Size(390, 844)]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('no overflow $locale ${size.width}x${size.height} x$scale',
            (tester) async {
          await _pump(tester, _api(),
              locale: locale, size: size, textScale: scale);
          expect(tester.takeException(), isNull);
          await tester.drag(
              find.byType(ListView).first, const Offset(0, -1500));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  Future<int> firstRowTiles(WidgetTester tester) async {
    final tiles = tester.widgetList(find.byType(CategoryTile)).length;
    expect(tiles, 8);
    final tops = [
      for (var i = 0; i < tiles; i++)
        tester.getTopLeft(find.byType(CategoryTile).at(i)).dy
    ];
    return tops.where((y) => y == tops.first).length;
  }

  for (final locale in ['ru', 'kk', 'en']) {
    testWidgets('category grid has 4 columns from 360 px ($locale)',
        (tester) async {
      await _pump(tester, _api(), locale: locale, size: const Size(360, 800));
      expect(await firstRowTiles(tester), 4);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('category grid adapts below 360 px and with large text',
      (tester) async {
    await _pump(tester, _api(), size: const Size(320, 800));
    expect(await firstRowTiles(tester), 3);
    await _pump(tester, _api(), size: const Size(320, 3000), textScale: 2);
    expect(await firstRowTiles(tester), 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('only Food is active; inactive tiles are muted with Soon label',
      (tester) async {
    await _pump(tester, _api(marketplace: true),
        locale: 'kk', size: const Size(360, 800));
    // 6 inactive categories carry the localized "Жақында" badge.
    expect(
        find.descendant(
            of: find.byType(CategoryGrid), matching: find.text('Жақында')),
        findsNWidgets(6));
    final foodTile = find.ancestor(
        of: find.text('Тамақ'), matching: find.byType(CategoryTile));
    expect(tester.getSemantics(foodTile).label, contains('Қолжетімді'));
    final cars = find.ancestor(
        of: find.text('Авто'), matching: find.byType(CategoryTile));
    expect(tester.getSemantics(cars).label, contains('Жақында'));
  });

  testWidgets('renders in dark theme and tablet width without overflow',
      (tester) async {
    await _pump(tester, _api(),
        size: const Size(900, 1200), theme: KundeTheme.dark);
    expect(tester.takeException(), isNull);
    expect(find.text('Еда'), findsOneWidget);
  });
}
