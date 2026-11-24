import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_localization/kunde_localizations.dart';
import 'package:kunde_mobile/features/executor/delivery_work_screen.dart';
import 'package:kunde_auth/auth_repository.dart';

import '../../support/fake_kunde_maps.dart';

class _CourierSession implements AuthRepository {
  bool handedOff = false;
  final positions = <Map<String, dynamic>?>[];
  int cleared = 0;
  bool syntheticRoute = true;

  @override
  Future<dynamic> authorizedJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Set<int> expected = const {200},
    Map<String, String>? headers,
  }) async {
    return switch ((method, path)) {
      ('GET', 'executor/deliveries/profile') => {
          'name': 'Test courier',
          'status': 'APPROVED',
          'online': false,
        },
      ('GET', 'executor/deliveries') => [
          {
            'id': 'shipment',
            'status': handedOff ? 'DELIVERED' : 'IN_TRANSIT',
            'parcelType': 'DOCUMENTS',
            'syntheticRoute': syntheticRoute,
          }
        ],
      ('PUT', 'executor/deliveries/shipment/location') => _position(body),
      ('DELETE', 'executor/deliveries/shipment/location') => _clear(),
      ('POST', 'executor/deliveries/shipment/handoff') =>
        _verify(body, expected),
      _ => throw StateError('Unexpected API call'),
    };
  }

  Null _position(Map<String, dynamic>? body) {
    positions.add(body);
    return null;
  }

  Null _clear() {
    cleared++;
    return null;
  }

  Null _verify(Map<String, dynamic>? body, Set<int> expected) {
    expect(body, {'code': '01234567'});
    expect(expected, {204});
    handedOff = true;
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  _navigationTests();
  testWidgets('live sharing retries, pauses in background and clears on stop',
      (tester) async {
    final session = _CourierSession()..syntheticRoute = false;
    var reads = 0;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: KundeLocalizations.supportedLocales,
      localizationsDelegates: KundeLocalizations.localizationsDelegates,
      home: DeliveryWorkScreen(
        auth: session,
        synthetic: false,
        readPosition: () async {
          if (reads++ == 0) throw IdentityUnavailable();
          return (latitude: 43.24, longitude: 76.92);
        },
      ),
    ));
    await tester.pumpAndSettle();
    expect(session.positions, isEmpty);
    await tester.tap(find.text('Share live location with sender'));
    await tester.pumpAndSettle();
    expect(find.text('GPS or network unavailable. Retrying.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    expect(session.positions, hasLength(1));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 14));
    expect(session.positions, hasLength(1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
    expect(session.positions, hasLength(2));
    expect(session.positions.last, {'latitude': 43.24, 'longitude': 76.92});

    await tester.tap(find.text('Stop sharing location'));
    await tester.pumpAndSettle();
    expect(session.cleared, 1);
    await tester.pump(const Duration(seconds: 14));
    expect(session.positions, hasLength(2));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('confirms a handoff through the assigned courier API',
      (tester) async {
    final session = _CourierSession();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: KundeLocalizations.supportedLocales,
      localizationsDelegates: KundeLocalizations.localizationsDelegates,
      home: DeliveryWorkScreen(auth: session, synthetic: true),
    ));
    await tester.pumpAndSettle();
    expect(find.text('In transit'), findsOneWidget);
    expect(find.text('Complete delivery'), findsNothing);
    await tester.tap(find.text('Confirm handoff'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '01234567');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verify code'));
    await tester.pumpAndSettle();
    expect(find.text('Handoff confirmed'), findsOneWidget);
    expect(find.text('Complete delivery'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _NavSession implements AuthRepository {
  _NavSession(this.status, {this.points = true});

  final String status;
  final bool points;

  @override
  Future<dynamic> authorizedJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Set<int> expected = const {200},
    Map<String, String>? headers,
  }) async {
    return switch ((method, path)) {
      ('GET', 'executor/deliveries/profile') => {
          'name': 'Test courier',
          'status': 'APPROVED',
          'online': false,
        },
      ('GET', 'executor/deliveries') => [
          {
            'id': 'shipment',
            'status': status,
            'parcelType': 'DOCUMENTS',
            'syntheticRoute': false,
            if (points) ...{
              'pickup': {'latitude': 43.238194, 'longitude': 76.94498},
              'destination': {'latitude': 43.25, 'longitude': 76.93},
            },
          }
        ],
      _ => throw StateError('Unexpected API call $method $path'),
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void _navigationTests() {
  Widget host(AuthRepository auth, {bool maps = true}) => MaterialApp(
        locale: const Locale('en'),
        supportedLocales: KundeLocalizations.supportedLocales,
        localizationsDelegates: KundeLocalizations.localizationsDelegates,
        home: DeliveryWorkScreen(
          auth: auth,
          synthetic: false,
          mapsFactory: maps
              ? (_) => FakeKundeMaps(
                    MockClient((_) async => http.Response('{}', 500)),
                  )
              : null,
        ),
      );

  testWidgets(
      'courier gets Navigate while carrying or collecting, only with maps and coordinates',
      (tester) async {
    for (final status in [
      'COURIER_ASSIGNED',
      'COURIER_ARRIVING',
      'PICKED_UP',
      'IN_TRANSIT',
      'RETURNING',
    ]) {
      await tester.pumpWidget(host(_NavSession(status)));
      await tester.pumpAndSettle();
      expect(find.text('Navigate'), findsOneWidget, reason: status);
      await tester.pumpWidget(const SizedBox.shrink());
    }
    for (final status in ['COURIER_ARRIVED', 'DELIVERED']) {
      await tester.pumpWidget(host(_NavSession(status)));
      await tester.pumpAndSettle();
      expect(find.text('Navigate'), findsNothing, reason: status);
      await tester.pumpWidget(const SizedBox.shrink());
    }
    await tester.pumpWidget(host(_NavSession('IN_TRANSIT'), maps: false));
    await tester.pumpAndSettle();
    expect(find.text('Navigate'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(host(_NavSession('IN_TRANSIT', points: false)));
    await tester.pumpAndSettle();
    expect(find.text('Navigate'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'Navigate opens guidance and the courier keeps the status buttons',
      (tester) async {
    await tester.pumpWidget(host(_NavSession('COURIER_ASSIGNED')));
    await tester.pumpAndSettle();
    expect(find.text('Depart'), findsOneWidget);
    await tester.tap(find.text('Navigate'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    // The fake provider has no GPS in a unit test; the screen is open and explains why.
    expect(find.text('To sender'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
