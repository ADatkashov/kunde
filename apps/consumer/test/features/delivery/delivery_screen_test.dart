import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_localization/kunde_localizations.dart';
import 'package:kunde_mobile/features/delivery/delivery_api.dart';
import 'package:kunde_mobile/features/delivery/delivery_screen.dart';
import 'package:kunde_mobile/features/delivery/delivery_timeline.dart';
import 'package:kunde_auth/auth_repository.dart';

class _Session implements AuthRepository {
  @override
  Future<List<Map<String, dynamic>>> addresses() async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _HistorySession extends _Session {
  _HistorySession({this.failFirst = false});

  final bool failFirst;
  int reads = 0;

  @override
  Future<dynamic> authorizedJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Set<int> expected = const {200},
    Map<String, String>? headers,
  }) async {
    expect((method, path), ('GET', 'deliveries'));
    if (reads++ == 0 && failFirst) throw StateError('Fixture offline');
    return <Map<String, dynamic>>[];
  }
}

class _TimelineSession extends _Session {
  @override
  Future<dynamic> authorizedJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Set<int> expected = const {200},
    Map<String, String>? headers,
  }) async {
    expect((method, path), ('GET', 'deliveries/order-1/timeline'));
    return [
      {'status': 'CREATED', 'occurredAt': '2026-11-22T10:00:00Z'},
      {'status': 'IN_TRANSIT', 'occurredAt': '2026-11-22T10:15:00Z'},
    ];
  }
}

void main() {
  testWidgets('expands the recorded shipment progress in order',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: KundeLocalizations.supportedLocales,
      localizationsDelegates: KundeLocalizations.localizationsDelegates,
      home: Scaffold(
        body: DeliveryTimeline(
          api: DeliveryApi(_TimelineSession()),
          order: DeliveryOrder.fromJson({
            'id': 'order-1',
            'status': 'IN_TRANSIT',
            'pickupAddress': 'Pickup',
            'destinationAddress': 'Destination',
            'amountKzt': 100,
          }),
        ),
      ),
    ));
    expect(find.text('In transit'), findsNothing);
    await tester.tap(find.text('Delivery progress'));
    await tester.pumpAndSettle();
    expect(find.text('Created'), findsOneWidget);
    expect(find.text('In transit'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Created')).dy,
      lessThan(tester.getTopLeft(find.text('In transit')).dy),
    );
  });

  testWidgets('retries failed shipment history after reconnecting',
      (tester) async {
    final session = _HistorySession(failFirst: true);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: KundeLocalizations.supportedLocales,
      localizationsDelegates: KundeLocalizations.localizationsDelegates,
      home: DeliveryScreen(
          api: DeliveryApi(session), synthetic: false, intakeEnabled: false),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('No shipments yet.'), findsOneWidget);
    expect(session.reads, 2);
  });

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

  testWidgets('delivery header fits a narrow screen at 200% text size',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      theme: ThemeData.dark(),
      supportedLocales: KundeLocalizations.supportedLocales,
      localizationsDelegates: KundeLocalizations.localizationsDelegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2)),
        child: child!,
      ),
      home: DeliveryScreen(api: DeliveryApi(_Session()), synthetic: false),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Send a parcel'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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
