import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_mobile/core/localization/kunde_localizations.dart';
import 'package:kunde_mobile/features/identity/auth_repository.dart';
import 'package:kunde_mobile/features/rides_admin/ride_admin_dashboard.dart';

Map<String, dynamic> _summary({
  int total = 4,
  int active = 1,
  int completed = 2,
  int cancelled = 1,
  num fare = 2400,
  num? average = 1200,
}) =>
    {
      'total': total,
      'active': active,
      'completed': completed,
      'cancelled': cancelled,
      'synthetic': 0,
      'completedFareKzt': fare,
      'averageFareKzt': average,
      'currency': 'KZT',
      'byClass': [
        {'rideClass': 'ECONOMY', 'rides': 3},
        {'rideClass': 'MINIVAN', 'rides': 1},
      ],
      'perDay': [
        for (var day = 17; day <= 23; day++)
          {
            'day': '2026-11-$day',
            'rides': day == 23 ? 2 : 0,
          },
      ],
    };

Map<String, dynamic> _trip(
  String id,
  String status,
  String createdAt, {
  String? driver,
  String rideClass = 'ECONOMY',
  num fare = 1200,
}) =>
    {
      'id': id,
      'status': status,
      'driverId': driver,
      'fleetId': null,
      'createdAt': createdAt,
      'synthetic': false,
      'rideClass': rideClass,
      'fareKzt': fare,
    };

class _Auth implements AuthRepository {
  _Auth(this.summary, this.trips);
  final Map<String, dynamic> summary;
  final List<Map<String, dynamic>> trips;
  final calls = <String>[];

  @override
  Future<dynamic> authorizedJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Set<int> expected = const {200},
    Map<String, String>? headers,
  }) async {
    calls.add('$method $path');
    return switch ((method, path)) {
      ('GET', 'admin/rides/summary') => summary,
      ('GET', 'admin/rides/trips') => trips,
      _ => throw StateError('Unexpected $method $path'),
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(AuthRepository auth, {String language = 'en'}) => MaterialApp(
      locale: Locale(language),
      supportedLocales: KundeLocalizations.supportedLocales,
      localizationsDelegates: KundeLocalizations.localizationsDelegates,
      home: RideAdminDashboard(auth: auth),
    );

void main() {
  test('stats come from the server summary and keep the newest rows', () {
    final stats = RideAdminStats.fromJson(_summary(), [
      _trip('a', 'COMPLETED', '2026-11-22T09:00:00Z'),
      _trip('b', 'IN_PROGRESS', '2026-11-23T09:00:00Z'),
    ]);
    expect(stats.total, 4);
    expect(stats.completedFare, 2400);
    expect(stats.averageFare, 1200);
    expect(stats.byClass, {'ECONOMY': 3, 'MINIVAN': 1});
    expect(stats.perDay, [0, 0, 0, 0, 0, 0, 2]);
    expect(stats.days.last, DateTime(2026, 11, 23));
    expect(stats.other, 0);
    expect(stats.recent.first['id'], 'b');
  });

  testWidgets('dashboard shows server fare totals, classes and recent fares',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final auth = _Auth(_summary(), [
      _trip('11111111-aaaa', 'COMPLETED', '2026-11-23T05:00:00Z',
          driver: '22222222-bbbb', rideClass: 'MINIVAN', fare: 1250),
      _trip('33333333-cccc', 'CANCELLED_BY_SYSTEM', '2026-11-22T05:00:00Z'),
    ]);
    await tester.pumpWidget(_app(auth));
    await tester.pumpAndSettle();

    expect(auth.calls, ['GET admin/rides/summary', 'GET admin/rides/trips']);
    expect(find.text('Total rides'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('2 400 KZT'), findsOneWidget);
    expect(find.text('1 200 KZT'), findsNWidgets(2)); // average + a row
    expect(find.text('1 250 KZT'), findsOneWidget);
    expect(find.text('Ride classes'), findsOneWidget);
    expect(find.text('Economy'), findsWidgets);
    expect(find.text('75%'), findsOneWidget); // economy share of 4 rides
    expect(find.text('KND-111111'), findsOneWidget);
    expect(find.text('KND-222222'), findsOneWidget);
    // Totals are tariff fares, and the page says payment is not connected.
    expect(find.textContaining('payment is not connected'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('with no completed ride the average is a dash, not zero',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(_Auth(
      _summary(
          total: 0,
          active: 0,
          completed: 0,
          cancelled: 0,
          fare: 0,
          average: null)
        ..['byClass'] = <Map<String, dynamic>>[],
      const [],
    )));
    await tester.pumpAndSettle();

    expect(find.text('Average ride'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('No rides yet'), findsOneWidget);
    expect(find.text('0%'), findsWidgets);
  });
}
