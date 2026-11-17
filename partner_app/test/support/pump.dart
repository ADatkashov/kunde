import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_backend.dart';

/// Lets real (mock-client) async work finish, then renders frames.
Future<void> settle(WidgetTester tester, {int ms = 40}) async {
  await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Signs in and (by default) opens the tab labelled [tab].
Future<void> pumpReady(WidgetTester tester, Harness h,
    {String? tab = 'Заказы'}) async {
  tester.view.physicalSize = const Size(1080, 2160);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.runAsync(h.controller.bootstrap);
  await tester.pumpWidget(h.app);
  await settle(tester);
  if (tab != null && find.byType(NavigationBar).evaluate().isNotEmpty) {
    await tester.tap(find.descendant(
        of: find.byType(NavigationBar), matching: find.text(tab)));
    await tester.pumpAndSettle();
  }
}

Future<void> pumpLogin(WidgetTester tester, Harness h) async {
  tester.view.physicalSize = const Size(1080, 2160);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.runAsync(h.controller.bootstrap);
  await tester.pumpWidget(h.app);
  await tester.pump();
}
