import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_maps_sdk/kunde_maps_sdk.dart';
import 'package:kunde_mobile/core/localization/kunde_localizations.dart';
import 'package:kunde_mobile/features/executor/driver_navigation_screen.dart';
import 'package:kunde_mobile/features/executor/executor_api.dart';
import 'package:kunde_mobile/features/executor/executor_screen.dart';
import 'package:kunde_mobile/features/identity/auth_repository.dart';
import 'package:kunde_mobile/features/maps/kunde_maps.dart';

// A real route response captured from the deployed DEV Maps Platform.
final _route = File(
  '../backend/app/src/test/resources/maps/routes-200.json',
).readAsBytesSync();

class _Gps implements LocationSource {
  _Gps(this.grant, {this.fix});

  GpsAccess grant;
  LocationFix? fix;
  final fixes = StreamController<LocationFix>.broadcast();
  final notificationFlags = <bool>[];

  @override
  Future<GpsAccess> access() async => grant;

  @override
  Future<LocationFix?> current({
    Duration timeout = const Duration(seconds: 12),
  }) async =>
      fix;

  @override
  Stream<LocationFix> watch({
    required MapsStrings strings,
    bool navigation = false,
    bool vehicle = true,
    bool notification = true,
  }) {
    notificationFlags.add(notification);
    return fixes.stream;
  }
}

class _Voice implements VoiceGuide {
  @override
  Future<bool> speak(
          String language, String text, bool Function() active) async =>
      true;

  @override
  Future<void> stop() async {}
}

KundeMaps _maps(http.Client client) => KundeMaps(
      client: client,
      config: MapsConfig(
        environment: MapsEnvironment.dev,
        searchUrl: 'https://search.test',
        routingUrl: 'https://routing.test',
        tileUrl: 'https://tiles.test/k.pmtiles',
        webUrl: 'https://web.test',
        language: 'en',
      ),
    );

Widget _app(Widget home) => MaterialApp(
      locale: const Locale('en'),
      supportedLocales: KundeLocalizations.supportedLocales,
      localizationsDelegates: KundeLocalizations.localizationsDelegates,
      home: home,
    );

LocationFix _at(double lat, double lon) =>
    LocationFix(GeoPoint(lat, lon), 6, DateTime.now());

class _Driver implements AuthRepository {
  _Driver({required this.maps, required this.status, this.withPoints = true});

  final bool maps;
  final String status;
  final bool withPoints;

  @override
  bool get authenticated => true;

  @override
  Future<dynamic> authorizedJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Set<int> expected = const {200},
    Map<String, String>? headers,
  }) async {
    switch (path) {
      case 'capabilities':
        return {'mapsEnabled': maps, 'deliveryExecutorEnabled': false};
      case 'executor/deliveries':
      case 'executor/leisure/assignments':
      case 'executor/education/sessions':
      case 'executor/auto/jobs':
        return <dynamic>[];
      case 'executor/rides/profile':
        return {
          'displayName': 'Test driver',
          'status': 'APPROVED',
          'online': false,
          'vehicle': {
            'description': 'Car',
            'plate': 'T1',
            'status': 'APPROVED'
          },
        };
      case 'executor/rides/trips':
        return [
          {
            'id': 'trip',
            'status': status,
            'createdAt': '2026-11-22T10:00:00Z',
            if (withPoints) ...{
              'pickup': {'latitude': 43.238194, 'longitude': 76.94498},
              'destination': {'latitude': 43.25, 'longitude': 76.93},
            },
          },
        ];
    }
    throw StateError('$method $path');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The map shows an indeterminate progress indicator while its style loads, so
/// pumpAndSettle would never finish; pump a fixed number of frames instead.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('ExecutorTrip route points', () {
    ExecutorTrip trip(String status, [Map<String, dynamic>? extra]) =>
        ExecutorTrip({
          'id': 't',
          'status': status,
          'createdAt': '2026-11-22T10:00:00Z',
          'pickup': {'latitude': 43.2, 'longitude': 76.9},
          'destination': {'latitude': 43.3, 'longitude': 76.8},
          ...?extra,
        });

    test('guides to the passenger first, then to the destination', () {
      expect(
          trip('DRIVER_ASSIGNED').navigationTarget, const GeoPoint(43.2, 76.9));
      expect(
          trip('DRIVER_ARRIVING').navigationTarget, const GeoPoint(43.2, 76.9));
      expect(trip('DRIVER_ARRIVED').navigationTarget, isNull);
      expect(trip('IN_PROGRESS').navigationTarget, const GeoPoint(43.3, 76.8));
      expect(trip('COMPLETED').navigationTarget, isNull);
    });

    test('missing or invalid points mean no navigation, never a crash', () {
      expect(
          trip('IN_PROGRESS', {'destination': null}).navigationTarget, isNull);
      expect(
        trip('DRIVER_ASSIGNED', {
          'pickup': {'latitude': 999, 'longitude': 76.9},
        }).navigationTarget,
        isNull,
      );
      expect(trip('DRIVER_ASSIGNED', {'pickup': 'x'}).navigationTarget, isNull);
    });
  });

  group('Executor screen', () {
    testWidgets(
        'shows Navigate for an active trip only when the server enables maps',
        (tester) async {
      for (final enabled in [true, false]) {
        await tester.pumpWidget(
          _app(
            ExecutorScreen(
              auth: _Driver(maps: enabled, status: 'DRIVER_ASSIGNED'),
              checkDeliveryMode: true,
              mapsFactory: (_) =>
                  _maps(MockClient((_) async => http.Response('{}', 500))),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Navigate'), enabled ? findsOneWidget : findsNothing);
        // The status step button is always there: the backend owns trip state.
        expect(find.widgetWithText(FilledButton, 'Depart'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets('no Navigate button when the server sent no coordinates',
        (tester) async {
      await tester.pumpWidget(
        _app(
          ExecutorScreen(
            auth: _Driver(
                maps: true, status: 'DRIVER_ASSIGNED', withPoints: false),
            checkDeliveryMode: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Navigate'), findsNothing);
    });
  });

  group('Driver navigation screen', () {
    const target = GeoPoint(43.25, 76.93);
    late List<Uri> requests;
    setUp(() => requests = []);

    http.Client routing({int failures = 0}) {
      var left = failures;
      return MockClient((request) async {
        requests.add(request.url);
        if (left > 0) {
          left--;
          return http.Response('{}', 500);
        }
        return http.Response.bytes(_route, 200);
      });
    }

    testWidgets(
        'routes from the real position and shows guidance with foreground-only GPS',
        (tester) async {
      final gps = _Gps(GpsAccess.ok, fix: _at(43.238194, 76.94498));
      await tester.pumpWidget(
        _app(
          DriverNavigationScreen(
            maps: _maps(routing()),
            target: target,
            title: 'To passenger',
            location: gps,
            voice: _Voice(),
          ),
        ),
      );
      await _settle(tester);

      expect(requests.single.path, '/v1/route');
      expect(requests.single.queryParameters['from'], '43.238194,76.944980');
      expect(requests.single.queryParameters['to'], '43.250000,76.930000');
      expect(find.text('End navigation'), findsOneWidget);
      expect(find.textContaining('Remaining:'), findsOneWidget);
      // No foreground service or notification: guidance only while the screen is open.
      expect(gps.notificationFlags, [false]);

      await tester.tap(find.text('End navigation'));
      await _settle(tester);
      expect(gps.fixes.hasListener, isFalse);
    });

    testWidgets(
        'denied location explains and offers Retry; granting it then works',
        (tester) async {
      final gps = _Gps(GpsAccess.deniedForever);
      await tester.pumpWidget(
        _app(
          DriverNavigationScreen(
            maps: _maps(routing()),
            target: target,
            title: 'To passenger',
            location: gps,
            voice: _Voice(),
          ),
        ),
      );
      await _settle(tester);
      expect(find.text('Location access is denied'), findsOneWidget);
      expect(requests, isEmpty);

      gps
        ..grant = GpsAccess.ok
        ..fix = _at(43.238194, 76.94498);
      await tester.tap(find.text('Retry'));
      await _settle(tester);
      expect(find.text('End navigation'), findsOneWidget);
    });

    testWidgets('no GPS fix is reported without calling the routing API',
        (tester) async {
      await tester.pumpWidget(
        _app(
          DriverNavigationScreen(
            maps: _maps(routing()),
            target: target,
            title: 'To passenger',
            location: _Gps(GpsAccess.ok),
            voice: _Voice(),
          ),
        ),
      );
      await _settle(tester);
      expect(find.text('Location is unavailable'), findsOneWidget);
      expect(requests, isEmpty);
    });

    testWidgets('a routing outage shows a message and Retry recovers',
        (tester) async {
      await tester.pumpWidget(
        _app(
          DriverNavigationScreen(
            maps: _maps(routing(failures: 1)),
            target: target,
            title: 'To passenger',
            location: _Gps(GpsAccess.ok, fix: _at(43.238194, 76.94498)),
            voice: _Voice(),
          ),
        ),
      );
      await _settle(tester);
      expect(find.text('Maps are temporarily unavailable.'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await _settle(tester);
      expect(find.text('End navigation'), findsOneWidget);
      expect(jsonDecode(utf8.decode(_route))['distance_m'], isA<num>());
    });
  });
}
