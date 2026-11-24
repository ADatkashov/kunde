import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_localization/kunde_localizations.dart';
import 'package:kunde_auth/auth_repository.dart';
import 'package:kunde_api/ride_api.dart';
import 'package:kunde_mobile/features/rides/rides_screen.dart';
import 'package:kunde_design/kunde_theme.dart';

import '../../support/premium_goldens.dart';

class _IdleAuth implements AuthRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FlakyHistory extends _IdleAuth {
  int reads = 0;

  @override
  Future<dynamic> authorizedJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Set<int> expected = const {200},
    Map<String, String>? headers,
  }) async {
    expect((method, path), ('GET', 'rides'));
    if (reads++ == 0) throw IdentityUnavailable();
    return [
      {
        'id': 'test-ride',
        'estimateKzt': 460,
        'status': 'COMPLETED',
        'createdAt': '2026-11-19T03:00:00Z',
      },
    ];
  }
}

void main() {
  testWidgets('retries history after a network failure', (tester) async {
    final session = _FlakyHistory();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: KundeLocalizations.supportedLocales,
      localizationsDelegates: KundeLocalizations.localizationsDelegates,
      home: RidesScreen(api: RideApi(session)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('History'));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Ride complete'), findsOneWidget);
    expect(session.reads, 2);
  });

  testWidgets('shows a safe starting screen with no fare until addresses exist',
      (tester) async {
    final boundary = GlobalKey();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(loadPremiumFonts);
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: KundeTheme.light,
          locale: const Locale('ru'),
          supportedLocales: KundeLocalizations.supportedLocales,
          localizationsDelegates: KundeLocalizations.localizationsDelegates,
          home: RidesScreen(api: RideApi(_IdleAuth())),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Откуда'), findsOneWidget);
    expect(find.text('Куда'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Узнать стоимость'),
    );
    expect(button.enabled, isFalse);
    expect(find.textContaining('KZT'), findsNothing);

    final captureDir = Platform.environment['KUNDE_RIDES_SCREENSHOT_DIR'];
    if (captureDir != null) {
      await tester.runAsync(() async {
        final render = boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 2);
        try {
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('$captureDir/consumer-rides-home.png');
          await file.writeAsBytes(png!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
    }
  });
}
