import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_mobile/core/localization/kunde_localizations.dart';
import 'package:kunde_mobile/features/identity/auth_repository.dart';
import 'package:kunde_mobile/features/rides_admin/ride_admin_dashboard.dart';

class _Auth implements AuthRepository {
  _Auth(this.rows);
  final List<Map<String, dynamic>> rows;

  @override
  Future<dynamic> authorizedJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Set<int> expected = const {200},
    Map<String, String>? headers,
  }) async {
    expect((method, path), ('GET', 'admin/rides/trips'));
    return rows;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _trip(String id, String status, String createdAt,
        {String? driver}) =>
    {
      'id': id,
      'status': status,
      'driverId': driver,
      'fleetId': null,
      'createdAt': createdAt,
      'synthetic': false,
    };

Widget _app(AuthRepository auth) => MaterialApp(
      locale: const Locale('en'),
      supportedLocales: KundeLocalizations.supportedLocales,
      localizationsDelegates: KundeLocalizations.localizationsDelegates,
      home: RideAdminDashboard(
        auth: auth,
        now: () => DateTime(2026, 11, 23, 12),
      ),
    );

void main() {
  test('stats count real statuses and bucket the last seven days', () {
    final stats = RideAdminStats.from([
      _trip('a', 'COMPLETED',
          DateTime(2026, 11, 23, 9).toUtc().toIso8601String()),
      _trip('b', 'IN_PROGRESS',
          DateTime(2026, 11, 23, 10).toUtc().toIso8601String()),
      _trip('c', 'CANCELLED_BY_CUSTOMER',
          DateTime(2026, 11, 22, 10).toUtc().toIso8601String()),
      _trip('d', 'NO_DRIVER_AVAILABLE',
          DateTime(2026, 11, 10, 10).toUtc().toIso8601String()),
    ], DateTime(2026, 11, 23, 12));
    expect(stats.total, 4);
    expect(stats.completed, 1);
    expect(stats.active, 1);
    expect(stats.cancelled, 1);
    expect(stats.other, 1);
    // Oldest to newest: only 22 and 23 November fall inside the window.
    expect(stats.perDay, [0, 0, 0, 0, 0, 1, 2]);
    expect(stats.recent.first['id'], 'b');
  });

  testWidgets('dashboard shows real counts and no invented money',
      (tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(_Auth([
      _trip('11111111-aaaa', 'COMPLETED', '2026-11-23T05:00:00Z',
          driver: '22222222-bbbb'),
      _trip('33333333-cccc', 'CANCELLED_BY_SYSTEM', '2026-11-22T05:00:00Z'),
    ])));
    await tester.pumpAndSettle();

    expect(find.text('Total rides'), findsOneWidget);
    expect(find.text('2'), findsOneWidget); // total
    expect(find.text('KND-111111'), findsOneWidget);
    expect(find.text('KND-222222'), findsOneWidget);
    expect(find.text('50%'), findsNWidgets(2));
    expect(find.textContaining('KZT'), findsNothing);
    expect(find.textContaining('₸'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty list shows zero shares and the empty table message',
      (tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(_Auth(const [])));
    await tester.pumpAndSettle();
    expect(find.text('No rides yet'), findsOneWidget);
    expect(find.text('0%'), findsNWidgets(4));
  });
}
