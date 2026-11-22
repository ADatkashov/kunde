import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_mobile/core/localization/kunde_localizations.dart';
import 'package:kunde_mobile/features/delivery/delivery_api.dart';
import 'package:kunde_mobile/features/delivery/delivery_screen.dart';
import 'package:kunde_mobile/features/identity/auth_repository.dart';
import 'package:kunde_mobile/features/rides/ride_map_panels.dart';

import '../../support/fake_kunde_maps.dart';

// A real route response captured from the deployed DEV Maps Platform.
final _route = File(
  '../backend/src/test/resources/maps/routes-200.json',
).readAsBytesSync();

class _Auth implements AuthRepository {
  @override
  Future<List<Map<String, dynamic>>> addresses() async => [];

  @override
  Future<dynamic> authorizedJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Set<int> expected = const {200},
    Map<String, String>? headers,
  }) async {
    switch ((method, path)) {
      case ('GET', 'deliveries'):
        return [_order];
      case ('GET', 'deliveries/d1'):
        return _order;
      case ('GET', 'deliveries/d1/location'):
        return {'latitude': 43.2401, 'longitude': 76.9402};
    }
    throw StateError('Unexpected call $method $path');
  }

  static const _order = <String, dynamic>{
    'id': 'd1',
    'status': 'IN_TRANSIT',
    'pickupAddress': 'Pickup street 1',
    'destinationAddress': 'Destination street 2',
    'amountKzt': 900,
    'syntheticRoute': false,
    'courier': {'name': 'Courier'},
  };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(Widget home) => MaterialApp(
      locale: const Locale('en'),
      supportedLocales: KundeLocalizations.supportedLocales,
      localizationsDelegates: KundeLocalizations.localizationsDelegates,
      home: home,
    );

http.Client _routing() =>
    MockClient((_) async => http.Response.bytes(_route, 200));

void main() {
  testWidgets(
      'with maps the address sheet offers the map and a route preview appears',
      (tester) async {
    final maps = FakeKundeMaps(_routing(), [
      searchResult('Sender yard', 43.238194, 76.94498),
      searchResult('Recipient office', 43.25, 76.93),
    ]);
    await tester.pumpWidget(
      _app(DeliveryScreen(
          api: DeliveryApi(_Auth()), synthetic: false, maps: maps)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pickup'));
    await tester.pumpAndSettle();
    expect(find.text('Pick on the map'), findsOneWidget);
    await tester.tap(find.text('Pick on the map'));
    await tester.pumpAndSettle();
    expect(find.text('Sender yard'), findsOneWidget);
    expect(find.byType(RideRoutePreviewPanel), findsNothing);

    await tester.tap(find.text('Destination'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pick on the map'));
    await tester.pumpAndSettle();
    expect(find.text('Recipient office'), findsOneWidget);

    expect(maps.titles, ['Pickup', 'Destination']);
    expect(find.text('map:pickup,destination:route'), findsOneWidget);
    expect(find.text('Distance'), findsOneWidget);
    expect(find.text('Typical time, traffic not included'), findsOneWidget);
    // The preview is a route, never a delivery price.
    expect(find.textContaining('₸'), findsNothing);
  });

  testWidgets('cancelling the map picker leaves the address unchanged',
      (tester) async {
    final maps = FakeKundeMaps(_routing());
    await tester.pumpWidget(
      _app(DeliveryScreen(
          api: DeliveryApi(_Auth()), synthetic: false, maps: maps)),
    );
    await tester.tap(find.text('Pickup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pick on the map'));
    await tester.pumpAndSettle();
    expect(maps.titles, ['Pickup']);
    expect(find.byType(RideRoutePreviewPanel), findsNothing);
  });

  testWidgets(
      'without maps the address sheet is the existing saved-address list',
      (tester) async {
    await tester.pumpWidget(
      _app(DeliveryScreen(api: DeliveryApi(_Auth()), synthetic: false)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pickup'));
    await tester.pumpAndSettle();
    expect(find.text('Pick on the map'), findsNothing);
    expect(find.text('Add an address in Profile.'), findsOneWidget);
  });

  testWidgets('tracking shows the courier on the map instead of raw numbers',
      (tester) async {
    final maps = FakeKundeMaps(_routing());
    await tester.pumpWidget(
      _app(
        DeliveryScreen(
          api: DeliveryApi(_Auth()),
          synthetic: false,
          intakeEnabled: false,
          maps: maps,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pickup street 1 → Destination street 2'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('map:driver:none'), findsOneWidget);
    expect(find.text('43.24010, 76.94020'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
  });
}
