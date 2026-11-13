import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_mobile/core/localization/kunde_localizations.dart';
import 'package:kunde_mobile/features/home/data/kunde_api.dart';
import 'package:kunde_mobile/features/home/presentation/home_screen.dart';
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
  testWidgets('shows Super App layout with honest unavailable states',
      (tester) async {
    await _pump(tester, _api(), size: const Size(390, 2400));

    expect(find.text('Алматы'), findsWidgets);
    expect(find.text('Что хотите сделать сегодня?'), findsOneWidget);
    expect(find.text('Еда'), findsOneWidget);
    expect(find.text('Продукты'), findsOneWidget);
    expect(find.text('Рядом с вами'), findsOneWidget);
    // Every category is "soon" while the marketplace is disabled.
    expect(find.text('Скоро'), findsWidgets);
    expect(find.text('Пока нет ресторанов'), findsOneWidget);
    expect(find.text('Сервисы пока не запущены'), findsOneWidget);
    expect(find.text('Сервер доступен'), findsOneWidget);
    expect(find.textContaining('KUNDE AI пока недоступен'), findsWidgets);
    // No invented restaurants, ratings or delivery times.
    expect(find.text('BurgerHouse'), findsNothing);
    expect(find.textContaining('мин'), findsNothing);
    expect(find.text('Еда и покупки'), findsNothing);
  });

  testWidgets('inactive category opens info sheet and offers no order',
      (tester) async {
    await _pump(tester, _api());
    await tester.tap(find.text('Поездки'));
    await tester.pumpAndSettle();
    expect(find.text('Скоро в KUNDE'), findsOneWidget);
    expect(find.text('Закрыть'), findsOneWidget);
    await tester.tap(find.text('Закрыть'));
    await tester.pumpAndSettle();
    expect(find.text('Скоро в KUNDE'), findsNothing);
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

  testWidgets('renders in dark theme and tablet width without overflow',
      (tester) async {
    await _pump(tester, _api(),
        size: const Size(900, 1200), theme: KundeTheme.dark);
    expect(tester.takeException(), isNull);
    expect(find.text('Еда'), findsOneWidget);
  });
}
