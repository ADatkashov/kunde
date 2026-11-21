import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_mobile/core/localization/kunde_localizations.dart';
import 'package:kunde_mobile/features/identity/auth_repository.dart';
import 'package:kunde_mobile/features/rides_admin/ride_admin_screen.dart';

class _AdminSession implements AuthRepository {
  _AdminSession({this.scoped = false, this.homeCatalog = false});

  final bool scoped;
  final bool homeCatalog;

  @override
  Future<dynamic> authorizedJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Set<int> expected = const {200},
    Map<String, String>? headers,
  }) async {
    if (method == 'GET' && Uri.parse(path).path == 'admin/deliveries/summary') {
      return <String, dynamic>{'total': 0, 'byStatus': []};
    }
    if (scoped && (method, path) == ('GET', 'admin/deliveries')) {
      return [
        <String, dynamic>{'id': 'shipment-1', 'status': 'DELIVERY_FAILED'},
      ];
    }
    if (homeCatalog &&
        (method, path) ==
            ('GET', 'admin/home-services/categories?limit=20&offset=0')) {
      return [];
    }
    expect((method, path), ('GET', 'admin/me/capabilities'));
    return <String, dynamic>{
      'permissions': [
        if (!scoped && !homeCatalog) 'DELIVERY_OPERATIONS',
        if (homeCatalog) 'HOME_SERVICES_CATALOG',
      ],
      'deliveryShipmentRead': scoped,
    };
  }

  @override
  Future<bool> logout() async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('scoped Delivery reader sees only shipments and audit',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: KundeLocalizations.supportedLocales,
      localizationsDelegates: KundeLocalizations.localizationsDelegates,
      home: RideAdminScreen(auth: _AdminSession(scoped: true)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Couriers'), findsNothing);
    expect(find.text('Delivery complaints'), findsNothing);
    expect(find.text('Home services categories'), findsNothing);
    await tester.ensureVisible(find.text('Shipments'));
    await tester.tap(find.text('Shipments'));
    await tester.pumpAndSettle();
    expect(find.text('shipment-1'), findsOneWidget);
    expect(find.text('Audit trail'), findsOneWidget);
    expect(find.text('Request return'), findsNothing);
  });

  testWidgets('Home Services catalog grant opens the category workspace',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: KundeLocalizations.supportedLocales,
      localizationsDelegates: KundeLocalizations.localizationsDelegates,
      home: RideAdminScreen(auth: _AdminSession(homeCatalog: true)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home services categories'));
    await tester.pumpAndSettle();
    expect(find.text('Add category'), findsOneWidget);
    expect(find.text('No categories on this page'), findsOneWidget);
  });

  for (final width in [320.0, 390.0, 600.0, 840.0, 1280.0, 1920.0]) {
    testWidgets('shows authorized queues at width $width with 200% text', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          supportedLocales: KundeLocalizations.supportedLocales,
          localizationsDelegates: KundeLocalizations.localizationsDelegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: RideAdminScreen(auth: _AdminSession()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Couriers'), findsOneWidget);
      expect(find.text('Shipments'), findsOneWidget);
      expect(find.text('Delivery complaints'), findsOneWidget);
      expect(find.text('Drivers'), findsNothing);
      expect(find.text('Auto bookings'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
