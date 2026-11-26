import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_partner/core/strings.dart';
import 'package:kunde_partner/data/partner_api.dart';
import 'package:kunde_partner/features/home_services/home_services_offers_screen.dart';

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
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
