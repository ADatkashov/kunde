import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_backend.dart';
import 'support/pump.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets(
        'orders screen meets tap-target, label and contrast guidelines (${dark ? 'dark' : 'light'})',
        (tester) async {
      final handle = tester.ensureSemantics();
      final h = Harness();
      await pumpReady(tester, h);
      if (dark) {
        await h.settings.setThemeMode(ThemeMode.dark);
        await tester.pumpAndSettle();
      }
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  }

  testWidgets('login screen is accessible', (tester) async {
    final handle = tester.ensureSemantics();
    final h = Harness(signedIn: false);
    await pumpLogin(tester, h);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    expect(find.bySemanticsLabel('Номер телефона'), findsWidgets);
    handle.dispose();
  });

  for (final width in [320.0, 360.0]) {
    testWidgets(
        'no overflow at ${width.toInt()} dp with 200% text on every tab',
        (tester) async {
      final h = Harness();
      tester.view.physicalSize = Size(width * 3, 640 * 3);
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await tester.runAsync(h.controller.bootstrap);
      await tester.pumpWidget(h.app);
      await settle(tester);
      for (final tab in ['Записи', 'Заведение', 'Профиль', 'Заказы']) {
        await tester.tap(find.descendant(
            of: find.byType(NavigationBar), matching: find.text(tab)));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: tab);
      }
    });
  }
}
