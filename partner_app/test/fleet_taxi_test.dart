import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_partner/core/strings.dart';
import 'package:kunde_partner/data/partner_api.dart';
import 'package:kunde_partner/data/partner_operations.dart';
import 'package:kunde_partner/features/business/fleet_screen.dart';

Map<String, dynamic> _fleet() => {
      'partnerId': 'p1',
      'status': 'APPROVED',
      'drivers': [
        {
          'id': 'd1',
          'name': 'Erlan K.',
          'status': 'APPROVED',
          'online': true,
          'vehicle': 'Hyundai Elantra',
          'plate': '774 AYA 02',
          'rideClass': 'COMFORT',
          'vehicleStatus': 'APPROVED',
        },
        {
          'id': 'd2',
          'name': 'Askat M.',
          'status': 'APPROVED',
          'online': false,
          'vehicle': null,
          'plate': null,
          'rideClass': null,
          'vehicleStatus': null,
        },
      ],
      'candidates': [
        {'id': 'c1', 'name': 'Danir S.'},
      ],
      'trips': [
        {
          'id': 't1',
          'status': 'COMPLETED',
          'driverId': 'd1',
          'createdAt': '2026-11-23T05:00:00Z',
          'synthetic': false,
        },
        {
          'id': 't2',
          'status': 'IN_PROGRESS',
          'driverId': 'd1',
          'createdAt': '2026-11-23T06:00:00Z',
          'synthetic': true,
        },
        {
          'id': 't3',
          'status': 'COMPLETED',
          'driverId': 'd2',
          'createdAt': '2026-11-20T06:00:00Z',
          'synthetic': false,
        },
      ],
      'stats': {'completed': 2, 'active': 1},
    };

Widget _app() {
  final api = PartnerApi(
    baseUri: Uri.parse('https://api.example.test/api/v1/'),
    accessToken: () async => 'fixture-token',
    client: MockClient((request) async {
      expect(request.url.path, '/api/v1/partner/partners/p1/rides/fleet');
      return http.Response(jsonEncode(_fleet()), 200,
          headers: {'content-type': 'application/json'});
    }),
  );
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: S.supported,
    localizationsDelegates: const [
      S.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    home: FleetScreen(
      ops: PartnerOperations(api, 'p1'),
      canManage: true,
      isOwner: true,
      now: () => DateTime.utc(2026, 11, 23, 12).toLocal(),
    ),
  );
}

void main() {
  testWidgets('service tab shows real KPIs, menu and coming-soon items',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('KUNDE Taxi'), findsWidgets);
    expect(find.text('Trips today'), findsOneWidget);
    // Two of the three trips were created on the fixed "today".
    expect(find.text('2'), findsNWidgets(2)); // today + completed
    expect(find.text('Completed'), findsWidgets);
    expect(find.text('Fleet management'), findsOneWidget);
    expect(find.text('Drivers and shifts'), findsOneWidget);
    expect(find.text('Tariffs and zones'), findsOneWidget);
    expect(find.text('Analytics'), findsOneWidget);
    expect(find.text('Soon'), findsNWidgets(2));
    // No revenue is shown: the backend does not provide it.
    expect(find.textContaining('KZT'), findsNothing);
    expect(find.textContaining('₸'), findsNothing);
  });

  testWidgets('menu opens the fleet and drivers tabs', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Fleet management'));
    await tester.pumpAndSettle();
    expect(find.text('Hyundai Elantra'), findsOneWidget);
    expect(find.text('774 AYA 02 · Comfort · Approved'), findsOneWidget);

    await tester.tap(find.widgetWithText(Tab, 'Drivers'));
    await tester.pumpAndSettle();
    expect(find.text('Erlan K.'), findsOneWidget);
    expect(find.text('Danir S.'), findsOneWidget);
    expect(find.text('Attach driver'), findsOneWidget);
  });
}
