import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_localization/kunde_localizations.dart';
import 'package:kunde_auth/auth_repository.dart';
import 'package:kunde_admin/features/rides_admin/ride_driver_access_screen.dart';

class _Admin implements AuthRepository {
  final posts = <String>[];
  final drivers = <String, Map<String, dynamic>>{
    'new': {
      'userId': 'new',
      'displayName': 'Erlan',
      'status': 'PENDING',
      'online': false,
      'vehicle': {
        'id': 'car-new',
        'description': 'Hyundai Elantra',
        'plate': '774AYA02',
        'rideClass': 'ECONOMY',
        'status': 'PENDING',
      },
    },
    'nocar': {
      'userId': 'nocar',
      'displayName': 'Askat',
      'status': 'PENDING',
      'online': false,
      'vehicle': null,
    },
    'ok': {
      'userId': 'ok',
      'displayName': 'Ruslan',
      'status': 'APPROVED',
      'online': true,
      'vehicle': {
        'id': 'car-ok',
        'description': 'Kia K5',
        'plate': '111AAA01',
        'rideClass': 'COMFORT',
        'status': 'APPROVED',
      },
    },
  };

  @override
  Future<dynamic> authorizedJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Set<int> expected = const {200},
    Map<String, String>? headers,
  }) async {
    if (method == 'GET' && path == 'admin/rides/drivers?includeReviewed=true') {
      return drivers.keys.toList();
    }
    if (method == 'GET' && path.startsWith('admin/rides/drivers/')) {
      return drivers[path.split('/').last];
    }
    if (method == 'POST' && path.endsWith('/decision')) {
      final id = path.split('/')[3];
      posts.add('$id ${body!['decision']} ${body['vehicleId'] ?? 'driver'}');
      final driver = drivers[id]!;
      if (body['vehicleId'] == null) {
        driver['status'] = body['decision'];
      } else {
        (driver['vehicle'] as Map<String, dynamic>)['status'] =
            body['decision'];
      }
      return driver;
    }
    throw StateError('$method $path');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(AuthRepository auth) => MaterialApp(
      locale: const Locale('en'),
      supportedLocales: KundeLocalizations.supportedLocales,
      localizationsDelegates: KundeLocalizations.localizationsDelegates,
      home: RideDriverAccessScreen(auth: auth),
    );

void main() {
  testWidgets(
      'waiting drivers show name and car; allow approves driver and car',
      (tester) async {
    final admin = _Admin();
    await tester.pumpWidget(_app(admin));
    await tester.pumpAndSettle();
    expect(find.text('Erlan'), findsOneWidget);
    expect(find.textContaining('774AYA02'), findsOneWidget);
    expect(find.text('Ruslan'), findsNothing);
    expect(find.text('Waiting · 2'), findsOneWidget);

    await tester.tap(find.byKey(const Key('driver-allow-new')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('driver-access-confirm')));
    await tester.pumpAndSettle();

    expect(admin.posts, ['new APPROVED driver', 'new APPROVED car-new']);
    expect(find.text('Erlan'), findsNothing);
    await tester.tap(find.byKey(const Key('driver-filter-cleared')));
    await tester.pumpAndSettle();
    expect(find.text('Erlan'), findsOneWidget);
    expect(find.text('Ruslan'), findsOneWidget);
  });

  testWidgets('a driver without a vehicle cannot be allowed on the line',
      (tester) async {
    await tester.pumpWidget(_app(_Admin()));
    await tester.pumpAndSettle();
    final button = tester
        .widget<FilledButton>(find.byKey(const Key('driver-allow-nocar')));
    expect(button.onPressed, isNull);
  });

  testWidgets('block sends one BLOCKED decision for the driver',
      (tester) async {
    final admin = _Admin();
    await tester.pumpWidget(_app(admin));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('driver-block-new')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('driver-access-confirm')));
    await tester.pumpAndSettle();
    expect(admin.posts, ['new BLOCKED driver']);
    await tester.tap(find.byKey(const Key('driver-filter-blocked')));
    await tester.pumpAndSettle();
    expect(find.text('Erlan'), findsOneWidget);
  });
}
