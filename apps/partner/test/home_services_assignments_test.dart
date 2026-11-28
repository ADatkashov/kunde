import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_partner/core/strings.dart';
import 'package:kunde_partner/data/partner_api.dart';
import 'package:kunde_partner/features/home_services/home_services_assignments_screen.dart';

http.Response _json(Object value) => http.Response(jsonEncode(value), 200,
    headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  testWidgets('submits selected master, reason and version and reloads queue',
      (tester) async {
    const root = '/api/v1/partner/partners/p1/home-services/assignments';
    var assigned = false;
    final api = PartnerApi(
      baseUri: Uri.parse('https://api.example.test/api/v1/'),
      accessToken: () async => 'token',
      client: MockClient((request) async {
        if (request.url.path == '$root/o1/masters') {
          return _json([
            {'id': 'm2', 'name': 'Master 2'},
          ]);
        }
        if (request.method == 'POST') {
          expect(request.url.path, '$root/o1');
          expect(jsonDecode(request.body), {
            'masterId': 'm2',
            'expectedVersion': 4,
            'reason': 'Replacement',
          });
          assigned = true;
          return http.Response('', 204);
        }
        return _json(assigned
            ? []
            : [
                {
                  'id': 'o1',
                  'bookingNumber': 'KND-101',
                  'serviceName': 'Cleaning',
                  'version': 4,
                }
              ]);
      }),
    );
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: S.supported,
      localizationsDelegates: const [S.delegate],
      home: HomeServicesAssignmentsScreen(
          api: api, partnerId: 'p1', canManage: true),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Assign a master'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Master 2').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), ' Replacement ');
    await tester.tap(find.text('Assign'));
    await tester.pumpAndSettle();
    expect(assigned, isTrue);
    expect(find.text('KND-101'), findsNothing);
  });
}
