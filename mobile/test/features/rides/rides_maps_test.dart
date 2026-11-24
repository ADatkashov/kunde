import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_maps_sdk/kunde_maps_sdk.dart';
import 'package:kunde_localization/kunde_localizations.dart';
import 'package:kunde_mobile/features/home/data/platform_snapshot.dart';
import 'package:kunde_auth/auth_repository.dart';
import 'package:kunde_api/ride_api.dart';
import 'package:kunde_mobile/features/rides/ride_map_panels.dart';
import 'package:kunde_ui/ride_widgets.dart' show rideFare;
import 'package:kunde_mobile/features/rides/rides_screen.dart';

import '../../support/fake_kunde_maps.dart';

// A real route response captured from the deployed DEV Maps Platform.
final _route = File(
  '../backend/app/src/test/resources/maps/routes-200.json',
).readAsBytesSync();

const _fares = {
  'ECONOMY': 435.14,
  'COMFORT': 1700,
  'BUSINESS': 3500,
  'MINIVAN': 4800,
};

class _Auth implements AuthRepository {
  final calls = <(String, String, Map<String, dynamic>?)>[];

  /// Classes the server has no tariff for (422 RIDE_CLASS_UNAVAILABLE).
  Set<String> unavailable = {};

  /// How many `POST rides` calls answer that the quote is gone.
  int staleQuotes = 0;

  /// The customer already has an active ride (409 RIDE_ALREADY_REQUESTED).
  bool activeRide = false;

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
        final value = body!['rideClass'] as String;
        if (unavailable.contains(value)) {
          throw IdentityApiError(422, 'RIDE_CLASS_UNAVAILABLE');
        }
        return {
          'id': 'quote-$value',
          'estimateKzt': _fares[value],
          'distanceMeters': 2508,
          'durationSeconds': 207,
          'synthetic': false,
        };
      case ('GET', 'rides'):
        return [_trip('SEARCHING_DRIVER')];
      case ('POST', 'rides/trip-1/dispatch'):
        return _trip('SEARCHING_DRIVER');
      case ('POST', 'rides'):
        if (activeRide) throw IdentityApiError(409, 'RIDE_ALREADY_REQUESTED');
        if (staleQuotes > 0) {
          staleQuotes--;
          throw IdentityApiError(409, 'RIDE_QUOTE_UNAVAILABLE');
        }
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
    'Taxi with maps: pick points, preview the route, the server prices every class',
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
      // No price before there is a route to price.
      expect(find.textContaining('₸'), findsNothing);
      expect(auth.calls.where((c) => c.$2 == 'rides/quotes'), isEmpty);

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
      expect(requests.single.path, '/v1/route');
      expect(requests.single.queryParameters['from'], '43.238194,76.944980');
      expect(requests.single.queryParameters['to'], '43.250000,76.930000');
      expect(requests.single.queryParameters['lang'], 'en');

      // All four classes are priced by the server, without a "Get fare" step.
      final quotes = auth.calls.where((c) => c.$2 == 'rides/quotes').toList();
      expect(quotes.map((c) => c.$3!['rideClass']).toSet(),
          {'ECONOMY', 'COMFORT', 'BUSINESS', 'MINIVAN'});
      for (final quote in quotes) {
        expect(quote.$3!['pickup'],
            {'latitude': 43.238194, 'longitude': 76.94498});
        expect(
            quote.$3!['destination'], {'latitude': 43.25, 'longitude': 76.93});
      }
      expect(find.text('Get fare'), findsNothing);
      expect(find.text('Minivan'), findsOneWidget);
      expect(find.text('435.14\u00A0₸'), findsOneWidget);
      expect(find.text('1\u00A0700\u00A0₸'), findsOneWidget);
      expect(find.text('3\u00A0500\u00A0₸'), findsOneWidget);
      expect(find.text('4\u00A0800\u00A0₸'), findsOneWidget);
      // The first class is selected and its price is on the order button.
      expect(
        find.widgetWithText(FilledButton, 'Order · 435.14\u00A0₸'),
        findsOneWidget,
      );

      await tester.tap(find.text('Comfort'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(FilledButton, 'Order · 1\u00A0700\u00A0₸'),
        findsOneWidget,
      );
      await tester
          .tap(find.widgetWithText(FilledButton, 'Order · 1\u00A0700\u00A0₸'));
      await tester.pumpAndSettle();
      final order =
          auth.calls.singleWhere((c) => c.$1 == 'POST' && c.$2 == 'rides');
      expect(order.$3, {'quoteId': 'quote-COMFORT'});
      // Stop the 5 s status poll before the test ends.
      await tester.pageBack();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('pickup starts at My location from the device position', (
    tester,
  ) async {
    final auth = _Auth();
    final maps = FakeKundeMaps(
      routing(),
      [_search('Abay 10', 43.25, 76.93)],
      const GeoPoint(43.238194, 76.94498),
    );
    await tester.pumpWidget(_app(RidesScreen(api: RideApi(auth), maps: maps)));
    await tester.pumpAndSettle();
    expect(find.text('My location'), findsOneWidget);
    expect(find.text('Pickup'), findsNothing);
    expect(auth.calls.where((c) => c.$2 == 'rides/quotes'), isEmpty);

    await tester.tap(find.text('Destination'));
    await tester.pumpAndSettle();
    final quote = auth.calls.firstWhere((c) => c.$2 == 'rides/quotes');
    expect(quote.$3!['pickup'], {'latitude': 43.238194, 'longitude': 76.94498});
    expect(maps.titles, ['Destination']);
    expect(find.widgetWithText(FilledButton, 'Order · 435.14\u00A0₸'),
        findsOneWidget);
  });

  testWidgets('an already active ride is explained and opened, not a failure',
      (tester) async {
    final auth = _Auth()..activeRide = true;
    final maps = FakeKundeMaps(
      routing(),
      [_search('Abay 10', 43.25, 76.93)],
      const GeoPoint(43.238194, 76.94498),
    );
    await tester.pumpWidget(_app(RidesScreen(api: RideApi(auth), maps: maps)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Destination'));
    await tester.pumpAndSettle();
    await tester
        .tap(find.widgetWithText(FilledButton, 'Order · 435.14\u00A0₸'));
    // The active ride page keeps polling, so settle by hand.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('The request failed. Try again.'), findsNothing);
    expect(
        auth.calls.where((c) => c.$1 == 'GET' && c.$2 == 'rides'), isNotEmpty);
    expect(find.text('Cancel ride'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a class without a tariff is not offered', (tester) async {
    final auth = _Auth()..unavailable = {'MINIVAN'};
    final maps = FakeKundeMaps(routing(), [
      _search('A', 43.238194, 76.94498),
      _search('B', 43.25, 76.93),
    ]);
    await tester.pumpWidget(_app(RidesScreen(api: RideApi(auth), maps: maps)));
    await tester.tap(find.text('Pickup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Destination'));
    await tester.pumpAndSettle();
    expect(find.text('Economy'), findsOneWidget);
    expect(find.text('Business'), findsOneWidget);
    expect(find.text('Minivan'), findsNothing);
    expect(find.text('The request failed. Try again.'), findsNothing);
  });

  testWidgets('an expired quote is re-priced instead of failing the order', (
    tester,
  ) async {
    final auth = _Auth()..staleQuotes = 1;
    final maps = FakeKundeMaps(routing(), [
      _search('A', 43.238194, 76.94498),
      _search('B', 43.25, 76.93),
    ]);
    await tester.pumpWidget(_app(RidesScreen(api: RideApi(auth), maps: maps)));
    await tester.tap(find.text('Pickup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Destination'));
    await tester.pumpAndSettle();
    final before = auth.calls.where((c) => c.$2 == 'rides/quotes').length;
    await tester
        .tap(find.widgetWithText(FilledButton, 'Order · 435.14\u00A0₸'));
    await tester.pumpAndSettle();
    expect(auth.calls.where((c) => c.$2 == 'rides/quotes').length, before + 4);
    expect(find.text('The price was updated. Check it and order again.'),
        findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Order · 435.14\u00A0₸'),
        findsOneWidget);
  });

  test('rideFare groups thousands and keeps cents only when present', () {
    expect(rideFare(1200), '1\u00A0200\u00A0₸');
    expect(rideFare(250000), '250\u00A0000\u00A0₸');
    expect(rideFare(435.14), '435.14\u00A0₸');
    expect(rideFare(0), '0\u00A0₸');
  });

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
    await tester
        .tap(find.widgetWithText(FilledButton, 'Order · 435.14\u00A0₸'));
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
