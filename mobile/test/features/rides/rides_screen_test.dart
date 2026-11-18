import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_mobile/core/localization/kunde_localizations.dart';
import 'package:kunde_mobile/features/identity/auth_repository.dart';
import 'package:kunde_mobile/features/rides/ride_api.dart';
import 'package:kunde_mobile/features/rides/rides_screen.dart';
import 'package:kunde_mobile/shared/theme/kunde_theme.dart';

import '../../support/premium_goldens.dart';

class _IdleAuth implements AuthRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
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
