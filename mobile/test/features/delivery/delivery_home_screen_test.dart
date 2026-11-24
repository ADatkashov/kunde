import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_localization/kunde_localizations.dart';
import 'package:kunde_mobile/features/delivery/delivery_api.dart';
import 'package:kunde_mobile/features/delivery/delivery_home_screen.dart';
import 'package:kunde_auth/auth_repository.dart';
import 'package:kunde_design/kunde_theme.dart';

import '../../support/premium_goldens.dart';

class _Session implements AuthRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final (locale, theme) in [
    ('ru', KundeTheme.light),
    ('kk', KundeTheme.dark),
  ]) {
    testWidgets('delivery home golden $locale', (tester) async {
      await tester.runAsync(loadPremiumFonts);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: Locale(locale),
        supportedLocales: KundeLocalizations.supportedLocales,
        localizationsDelegates: KundeLocalizations.localizationsDelegates,
        theme: theme,
        home:
            DeliveryHomeScreen(api: DeliveryApi(_Session()), synthetic: false),
      ));
      await premiumGolden(tester, 'delivery_home_$locale');
    });
  }

  testWidgets('Delivery home opens the existing shipment form at large text',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: KundeLocalizations.supportedLocales,
      localizationsDelegates: KundeLocalizations.localizationsDelegates,
      theme: ThemeData.dark(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2)),
        child: child!,
      ),
      home: DeliveryHomeScreen(api: DeliveryApi(_Session()), synthetic: false),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Send a parcel'), 160);
    await tester.tap(find.text('Send a parcel'));
    await tester.pumpAndSettle();
    expect(find.text('Pickup'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
