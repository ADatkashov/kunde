import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_partner/core/strings.dart';
import 'package:kunde_partner/data/partner_api.dart';
import 'package:kunde_partner/data/partner_operations.dart';
import 'package:kunde_partner/features/home_services/home_services_offers_screen.dart';

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  _formTests();
  test('partner transitions mirror the backend state machine', () {
    final action = HomeServicesOffersScreen.actionFor;
    expect(action('DRAFT'), 'SUBMIT');
    expect(action('REJECTED'), 'SUBMIT');
    expect(action('PENDING'), 'WITHDRAW');
    expect(action('PUBLISHED'), 'WITHDRAW');
    expect(action('SUSPENDED'), isNull);
  });

  testWidgets('manager submits a draft with its version; operator cannot',
      (tester) async {
    final posts = <String>[];
    var status = 'DRAFT';
    final api = PartnerApi(
      baseUri: Uri.parse('https://api.example.test/api/v1/'),
      accessToken: () async => 'token',
      client: MockClient((r) async {
        if (r.method == 'POST') {
          posts.add('${r.url.path} ${r.body}');
          status = 'PENDING';
          return _json({'id': 'o1', 'status': status});
        }
        return _json([
          {
            'id': 'o1',
            'serviceName': 'Генеральная уборка',
            'definitionCode': 'DEEP_CLEAN',
            'pricingModel': 'FROM',
            'status': status,
            'version': 1,
          },
        ]);
      }),
    );
    Widget app(bool canManage) => MaterialApp(
          locale: const Locale('en'),
          supportedLocales: S.supported,
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: HomeServicesOffersScreen(
              api: api, partnerId: 'p1', canManage: canManage),
        );

    await tester.pumpWidget(app(false));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('submit-o1')), findsNothing);

    await tester.pumpWidget(app(true));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('submit-o1')));
    await tester.pumpAndSettle();
    expect(posts, [
      '/api/v1/partner/partners/p1/home-services/offers/o1/transition {"action":"SUBMIT","expectedVersion":1}'
    ]);
    expect(find.byKey(const ValueKey('withdraw-o1')), findsOneWidget);
  });
}

void _formTests() {
  testWidgets('form creates a draft only for a CLEANING venue service',
      (tester) async {
    final posts = <String>[];
    final api = PartnerApi(
      baseUri: Uri.parse('https://api.example.test/api/v1/'),
      accessToken: () async => 'token',
      client: MockClient((r) async {
        final path = r.url.path;
        if (r.method == 'POST') {
          posts.add('$path ${r.body}');
          return _json({'id': 'o2', 'status': 'DRAFT'});
        }
        if (path.endsWith('/booking/venues')) {
          return _json([
            {
              'id': 'v1',
              'name': 'Clean Co',
              'open': true,
              'category': 'CLEANING'
            },
            {'id': 'v2', 'name': 'Barber', 'open': true, 'category': 'BARBER'},
          ]);
        }
        if (path.endsWith('/booking/venues/v1/services')) {
          return _json([
            {
              'id': 's1',
              'name': 'Уборка 1к',
              'durationMinutes': 120,
              'priceMinor': 1000000,
              'available': true,
            },
          ]);
        }
        if (path.endsWith('/home-services/definitions')) {
          return _json([
            {
              'code': 'DEEP_CLEAN',
              'categoryCode': 'CLEANING',
              'nameRu': 'Генеральная уборка',
              'nameKk': 'Күрделі жинау',
              'nameEn': 'Deep cleaning',
            },
          ]);
        }
        return _json([]);
      }),
    );
    final ops = PartnerOperations(api, 'p1');
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: S.supported,
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: HomeServicesOffersScreen(
          api: api, partnerId: 'p1', canManage: true, ops: ops),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('create-offer')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('venue')));
    await tester.pumpAndSettle();
    expect(find.text('Barber'), findsNothing);
    await tester.tap(find.text('Clean Co').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('service')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Уборка 1к').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('definition')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deep cleaning').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('warranty')), '14');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save-offer')));
    await tester.pumpAndSettle();

    expect(posts, [
      '/api/v1/partner/partners/p1/home-services/offers {"serviceId":"s1","definitionCode":"DEEP_CLEAN","pricingModel":"FIXED","homeVisit":true,"warrantyDays":14}'
    ]);
  });
}
