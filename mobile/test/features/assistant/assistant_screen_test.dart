import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_mobile/core/localization/kunde_localizations.dart';
import 'package:kunde_mobile/features/assistant/assistant_screen.dart';
import 'package:kunde_mobile/shared/theme/kunde_theme.dart';

import '../../support/premium_goldens.dart';

class _Gateway implements AssistantGateway {
  Completer<String> response = Completer<String>();
  final requests = <String>[];

  @override
  Future<List<AssistantMessage>> history() async => [
        (text: 'Previous reply', isUser: false),
      ];

  @override
  Future<String> send(String message) {
    requests.add(message);
    return response.future;
  }
}

Future<void> _open(WidgetTester tester, [AssistantGateway? gateway]) async {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: KundeTheme.dark,
    locale: const Locale('en'),
    localizationsDelegates: KundeLocalizations.localizationsDelegates,
    supportedLocales: KundeLocalizations.supportedLocales,
    home: AssistantScreen(gateway: gateway),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('dark assistant preview at 320 dp', (tester) async {
    await tester.runAsync(loadPremiumFonts);
    await _open(tester);
    await premiumGolden(tester, 'premium_assistant_dark_320');
  });

  testWidgets('without a gateway the assistant exposes no send action',
      (tester) async {
    await _open(tester);
    expect(find.textContaining('KUNDE AI is not available'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(
        tester
            .widget<IconButton>(find.byWidgetPredicate(
                (widget) => widget is IconButton && widget.tooltip == 'Send'))
            .onPressed,
        isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loads history and restores the draft after a failed send',
      (tester) async {
    final gateway = _Gateway();
    await _open(tester, gateway);
    expect(find.text('Previous reply'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Find a restaurant');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(gateway.requests, ['Find a restaurant']);
    gateway.response.completeError(Exception('offline'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Find a restaurant',
    );
    gateway.response = Completer<String>();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    gateway.response.complete('New reply');
    await tester.pumpAndSettle();
    expect(find.text('New reply'), findsOneWidget);
  });
}
