import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_mobile/core/localization/kunde_localizations.dart';
import 'package:kunde_mobile/features/delivery/delivery_api.dart';
import 'package:kunde_mobile/features/delivery/delivery_screen.dart';
import 'package:kunde_mobile/features/identity/auth_repository.dart';

class _Session implements AuthRepository {
  @override
  Future<List<Map<String, dynamic>>> addresses() async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _HistorySession extends _Session {
  @override
  Future<dynamic> authorizedJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Set<int> expected = const {200},
    Map<String, String>? headers,
  }) async {
    expect((method, path), ('GET', 'deliveries'));
    return <Map<String, dynamic>>[];
  }
}

void main() {
  testWidgets('disabled intake keeps history accessible with no create actions',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: KundeLocalizations.supportedLocales,
      localizationsDelegates: KundeLocalizations.localizationsDelegates,
      home: DeliveryScreen(
          api: DeliveryApi(_HistorySession()),
          synthetic: false,
          intakeEnabled: false),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Shipment history'), findsOneWidget);
    expect(find.text('Pickup'), findsNothing);
    expect(find.text('Get a quote'), findsNothing);
  });

  for (final entry
      in {'ru': 'Доставка', 'kk': 'Жеткізу', 'en': 'Delivery'}.entries) {
    testWidgets('opens the shipment form in ${entry.key}', (tester) async {
      await tester.pumpWidget(MaterialApp(
        locale: Locale(entry.key),
        supportedLocales: KundeLocalizations.supportedLocales,
        localizationsDelegates: KundeLocalizations.localizationsDelegates,
        home: DeliveryScreen(api: DeliveryApi(_Session()), synthetic: false),
      ));
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
      expect(find.byIcon(Icons.history_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('synthetic pickup is labeled and gated', (tester) async {
    for (final enabled in [false, true]) {
      await tester.pumpWidget(MaterialApp(
        key: ValueKey(enabled),
        locale: const Locale('en'),
        supportedLocales: KundeLocalizations.supportedLocales,
        localizationsDelegates: KundeLocalizations.localizationsDelegates,
        home: DeliveryScreen(api: DeliveryApi(_Session()), synthetic: enabled),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pickup'));
      await tester.pumpAndSettle();
      expect(find.text('[DEV/TEST] Pickup'),
          enabled ? findsOneWidget : findsNothing);
      final context = tester.element(find.byType(BottomSheet));
      Navigator.of(context).pop();
      await tester.pumpAndSettle();
    }
  });
}
