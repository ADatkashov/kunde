import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_mobile/core/localization/kunde_localizations.dart';
import 'package:kunde_mobile/features/executor/delivery_work_screen.dart';
import 'package:kunde_mobile/features/identity/auth_repository.dart';

import '../../support/fake_kunde_maps.dart';

class _CourierSession implements AuthRepository {
  bool handedOff = false;

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
            'syntheticRoute': true,
          }
        ],
      ('POST', 'executor/deliveries/shipment/handoff') =>
        _verify(body, expected),
      _ => throw StateError('Unexpected API call'),
    };
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
