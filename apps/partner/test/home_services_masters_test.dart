import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_partner/core/strings.dart';
import 'package:kunde_partner/data/partner_api.dart';
import 'package:kunde_partner/data/partner_operations.dart';
import 'package:kunde_partner/features/home_services/home_services_masters_screen.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json; charset=utf-8'});

const _masters = [
  {
    'id': 'm1',
    'venueId': 'v1',
    'venueName': 'Clean Co',
    'name': 'Алия',
    'linked': false,
    'inviteCode': 'HABCD-23456',
  },
  {
    'id': 'm2',
    'venueId': 'v1',
    'venueName': 'Clean Co',
    'name': 'Руслан',
    'linked': true,
    'inviteCode': null,
  },
];

PartnerApi _api(http.Client client) => PartnerApi(
    baseUri: Uri.parse('https://api.example.test/api/v1/'),
    accessToken: () async => 'token',
    client: client);

Widget _app(PartnerApi api, {bool canManage = true, PartnerOperations? ops}) =>
    MaterialApp(
      locale: const Locale('en'),
      supportedLocales: S.supported,
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: HomeServicesMastersScreen(
          api: api, partnerId: 'p1', canManage: canManage, ops: ops),
    );

void main() {
  testWidgets('shows the invite code only until the master has signed in',
      (tester) async {
    final api = _api(MockClient((r) async => _json(_masters)));
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    expect(find.text('Алия'), findsOneWidget);
    expect(find.byKey(const ValueKey('code-m1')), findsOneWidget);
    expect(find.text('HABCD-23456'), findsOneWidget);
    expect(find.byKey(const ValueKey('linked-m2')), findsOneWidget);
    expect(find.byKey(const ValueKey('code-m2')), findsNothing);
    // A linked master has no code to reissue, but can still be retired.
    expect(find.byKey(const ValueKey('reissue-m1')), findsOneWidget);
    expect(find.byKey(const ValueKey('reissue-m2')), findsNothing);
    expect(find.byKey(const ValueKey('deactivate-m2')), findsOneWidget);
  });

  testWidgets('an operator reads the team but sees no actions', (tester) async {
    final api = _api(MockClient((r) async => _json(_masters)));
    await tester.pumpWidget(_app(api, canManage: false));
    await tester.pumpAndSettle();
    expect(find.text('Алия'), findsOneWidget);
    expect(find.byKey(const ValueKey('reissue-m1')), findsNothing);
    expect(find.byKey(const ValueKey('deactivate-m1')), findsNothing);
    expect(find.byKey(const ValueKey('create-master')), findsNothing);
  });

  testWidgets('reissue posts to the master invite endpoint and reloads',
      (tester) async {
    final posts = <String>[];
    var code = 'HABCD-23456';
    final api = _api(MockClient((r) async {
      if (r.method == 'POST') {
        posts.add('${r.url.path} ${r.body}');
        code = 'HZZZZ-77777';
        return _json({'id': 'm1', 'inviteCode': code});
      }
      return _json([
        {..._masters[0], 'inviteCode': code},
      ]);
    }));
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reissue-m1')));
    await tester.pumpAndSettle();
    expect(posts,
        ['/api/v1/partner/partners/p1/home-services/masters/m1/invite {}']);
    expect(find.text('HZZZZ-77777'), findsOneWidget);
  });

  testWidgets('retiring a master asks first and then posts', (tester) async {
    final posts = <String>[];
    var retired = false;
    final api = _api(MockClient((r) async {
      if (r.method == 'POST') {
        posts.add(r.url.path);
        retired = true;
        return http.Response('', 204);
      }
      return _json(retired ? <Object>[] : _masters);
    }));
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('deactivate-m1')));
    await tester.pumpAndSettle();
    expect(posts, isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(posts, isEmpty);

    await tester.tap(find.byKey(const ValueKey('deactivate-m1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-deactivate')));
    await tester.pumpAndSettle();
    expect(posts,
        ['/api/v1/partner/partners/p1/home-services/masters/m1/deactivate']);
    expect(find.text('No masters yet'), findsOneWidget);
  });

  testWidgets('a refused retirement shows the failure and keeps the list',
      (tester) async {
    final api = _api(MockClient((r) async {
      if (r.method == 'POST') {
        return _json({
          'code': 'MASTER_HAS_BOOKINGS',
          'message': 'The master has active bookings',
        }, 409);
      }
      return _json(_masters);
    }));
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('deactivate-m1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-deactivate')));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Алия'), findsOneWidget);
  });

  testWidgets('creating a master offers only CLEANING venues and posts both',
      (tester) async {
    final posts = <String>[];
    final api = _api(MockClient((r) async {
      final path = r.url.path;
      if (r.method == 'POST') {
        posts.add('$path ${r.body}');
        return _json(
            {'id': 'm3', 'name': 'Айдос', 'inviteCode': 'HAAAA-22222'});
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
      return _json(_masters);
    }));
    final ops = PartnerOperations(api, 'p1');
    await tester.pumpWidget(_app(api, ops: ops));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('create-master')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('save-master')))
            .onPressed,
        isNull);

    await tester.tap(find.byKey(const ValueKey('master-venue')));
    await tester.pumpAndSettle();
    expect(find.text('Barber'), findsNothing);
    await tester.tap(find.text('Clean Co').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('master-name')), 'Айдос');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-master')));
    await tester.pumpAndSettle();
    expect(posts, [
      '/api/v1/partner/partners/p1/home-services/masters {"venueId":"v1","name":"Айдос"}'
    ]);
  });
}
