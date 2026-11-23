import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_maps_sdk/kunde_maps_sdk.dart';
import 'package:kunde_mobile/core/localization/kunde_localizations.dart';
import 'package:kunde_mobile/features/home/data/platform_snapshot.dart';
import 'package:kunde_mobile/features/identity/auth_repository.dart';
import 'package:kunde_mobile/features/rides/ride_api.dart';
import 'package:kunde_mobile/features/rides/ride_map_panels.dart';
import 'package:kunde_mobile/features/rides/rides_screen.dart';

import '../../support/fake_kunde_maps.dart';

// A real route response captured from the deployed DEV Maps Platform.
final _route = File(
  '../backend/src/test/resources/maps/routes-200.json',
).readAsBytesSync();

class _Auth implements AuthRepository {
  final calls = <(String, String, Map<String, dynamic>?)>[];

  @override
  Future<dynamic> authorizedJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Set<int> expected = const {200},
    Map<String, String>? headers,
  }) async {
    calls.add((method, path, body));
    switch ((method, path)) {
      case ('POST', 'rides/quotes'):
        return {
          'id': 'quote-1',
          'estimateKzt': 435.14,
          'distanceMeters': 2508,
          'durationSeconds': 207,
          'synthetic': false,
        };
      case ('POST', 'rides'):
        return _trip('DRIVER_ASSIGNED');
      case ('GET', 'rides/trip-1'):
        return _trip('DRIVER_ASSIGNED');
      case ('GET', 'rides/trip-1/location'):
        return {
          'point': {'latitude': 43.2401, 'longitude': 76.9402},
        };
    }
    throw StateError('Unexpected call $method $path');
  }

  static Map<String, dynamic> _trip(String status) => {
        'id': 'trip-1',
        'status': status,
        'estimateKzt': 435.14,
        'createdAt': '2026-11-22T10:00:00Z',
        'synthetic': false,
        'driver': {'name': 'Driver', 'vehicle': 'Car', 'plate': 'A1'},
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

PickedLocation _search(String name, double lat, double lon) =>
    searchResult(name, lat, lon);

void main() {
  late List<Uri> requests;
  late int failRoutes;

  http.Client routing() => MockClient((request) async {
        requests.add(request.url);
        if (failRoutes > 0) {
          failRoutes--;
          return http.Response('{}', 500);
        }
        return http.Response.bytes(_route, 200);
      });

  setUp(() {
    requests = [];
    failRoutes = 0;
  });

  testWidgets(
    'Taxi with maps: pick pickup and destination, preview the route, server prices the quote',
    (tester) async {
      final auth = _Auth();
      final maps = FakeKundeMaps(routing(), [
        _search('Abay 10', 43.238194, 76.94498),
        PickedLocation(const GeoPoint(43.25, 76.93)),
      ]);
      await tester.pumpWidget(
        _app(RidesScreen(api: RideApi(auth), maps: maps)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(RideRoutePreviewPanel), findsNothing);

      await tester.tap(find.text('Pickup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Destination'));
      await tester.pumpAndSettle();

      expect(maps.titles, ['Pickup', 'Destination']);
      expect(find.text('Abay 10'), findsOneWidget);
      // A dropped pin is labelled by coordinates, not by an invented address.
      expect(find.text('43.25000, 76.93000'), findsOneWidget);
      expect(find.text('map:pickup,destination:route'), findsOneWidget);
      expect(find.text('Distance'), findsOneWidget);
      expect(find.text('Typical time, traffic not included'), findsOneWidget);
      // The preview is route only: no price before the server quotes.
      expect(find.textContaining('KZT'), findsNothing);
      expect(requests.single.path, '/v1/route');
      expect(requests.single.queryParameters['from'], '43.238194,76.944980');
      expect(requests.single.queryParameters['to'], '43.250000,76.930000');
      expect(requests.single.queryParameters['lang'], 'en');

      await tester.scrollUntilVisible(
        find.widgetWithText(FilledButton, 'Get fare'),
        200,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Get fare'));
      await tester.pumpAndSettle();
      final quote = auth.calls.singleWhere((c) => c.$2 == 'rides/quotes');
      expect(
          quote.$3!['pickup'], {'latitude': 43.238194, 'longitude': 76.94498});
      expect(quote.$3!['destination'], {'latitude': 43.25, 'longitude': 76.93});
      expect(find.textContaining('435.14 KZT'), findsOneWidget);
    },
  );

  testWidgets('a failing route service shows a message and Retry recovers', (
    tester,
  ) async {
    failRoutes = 1;
    final maps = FakeKundeMaps(routing(), [
      _search('A', 43.238194, 76.94498),
      _search('B', 43.25, 76.93),
    ]);
    await tester.pumpWidget(
      _app(RidesScreen(api: RideApi(_Auth()), maps: maps)),
    );
    await tester.tap(find.text('Pickup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Destination'));
    await tester.pumpAndSettle();
    expect(find.text('Maps are temporarily unavailable.'), findsOneWidget);
    expect(find.text('Distance'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Distance'), findsOneWidget);
    expect(find.text('Maps are temporarily unavailable.'), findsNothing);
  });

  testWidgets('going back from the picker keeps the previous point', (
    tester,
  ) async {
    final picks = <PickedLocation>[_search('A', 43.238194, 76.94498)];
    final maps = FakeKundeMaps(routing(), picks);
    await tester.pumpWidget(
      _app(RidesScreen(api: RideApi(_Auth()), maps: maps)),
    );
    await tester.tap(find.text('Pickup'));
    await tester.pumpAndSettle();
    expect(find.text('A'), findsOneWidget);
    await tester.tap(find.text('Destination'));
    await tester.pumpAndSettle();
    expect(find.byType(RideRoutePreviewPanel), findsNothing);
    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('active trip shows the driver on the map instead of raw numbers',
      (
    tester,
  ) async {
    final auth = _Auth();
    final maps = FakeKundeMaps(routing(), [
      _search('A', 43.238194, 76.94498),
      _search('B', 43.25, 76.93),
    ]);
    await tester.pumpWidget(_app(RidesScreen(api: RideApi(auth), maps: maps)));
    await tester.tap(find.text('Pickup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Destination'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, 'Get fare'),
      200,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Get fare'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Request ride'));
    await tester.pumpAndSettle();

    expect(find.text('map:driver:none'), findsOneWidget);
    expect(find.text('43.24010, 76.94020'), findsNothing);
    // Stop the 5 s status poll before the test ends.
    await tester.pageBack();
    await tester.pumpAndSettle();
  });

  testWidgets('without maps the existing list-based address flow is unchanged',
      (
    tester,
  ) async {
    await tester.pumpWidget(_app(RidesScreen(api: RideApi(_Auth()))));
    await tester.tap(find.text('Pickup'));
    await tester.pumpAndSettle();
    // The legacy bottom sheet has a text field for the address query.
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(RideRoutePreviewPanel), findsNothing);
  });

  test('addressFrom keeps real names and never invents an address', () {
    final named = addressFrom(_search('Abay 10', 43.2, 76.9), 'en');
    expect(named.label, 'Abay 10');
    final pin = addressFrom(PickedLocation(const GeoPoint(43.2, 76.9)), 'ru');
    expect(pin.label, '43.20000, 76.90000');
    expect(pin.point, {'latitude': 43.2, 'longitude': 76.9});
    expect(pointOf(pin), const GeoPoint(43.2, 76.9));
  });

  test('platform snapshot reads mapsEnabled and defaults to off', () {
    Map<String, dynamic> base() => {
          'releaseStage': 'FOUNDATION',
          'marketplaceEnabled': false,
          'oidcIssuerConfigured': false,
          'aiEnabled': false,
        };
    expect(PlatformSnapshot.fromJson(base()).mapsEnabled, isFalse);
    expect(
      PlatformSnapshot.fromJson({...base(), 'mapsEnabled': true}).mapsEnabled,
      isTrue,
    );
    expect(
      PlatformSnapshot.fromJson({...base(), 'mapsEnabled': 'yes'}).mapsEnabled,
      isFalse,
    );
    expect(jsonEncode(base()), isNot(contains('mapsEnabled')));
  });
}
