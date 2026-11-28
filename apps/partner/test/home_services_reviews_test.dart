import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_partner/core/strings.dart';
import 'package:kunde_partner/data/partner_api.dart';
import 'package:kunde_partner/features/home_services/home_services_reviews_screen.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json; charset=utf-8'});

PartnerApi _api(http.Client client) => PartnerApi(
    baseUri: Uri.parse('https://api.example.test/api/v1/'),
    accessToken: () async => 'token',
    client: client);

Widget _app(PartnerApi api, {bool canComplain = true}) => MaterialApp(
      locale: const Locale('en'),
      supportedLocales: S.supported,
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: HomeServicesReviewsScreen(
          api: api, partnerId: 'p1', canComplain: canComplain),
    );

const _summary = {
  'organization': {'rating': 4.5, 'count': 2},
  'masters': [
    {'masterId': 'm1', 'masterName': 'Алия', 'rating': 4.5, 'count': 2},
    {'masterId': 'm2', 'masterName': 'Руслан', 'rating': null, 'count': 0},
  ],
};

Map<String, dynamic> _page(Iterable<int> ratings) => {
      'items': [
        for (final r in ratings)
          {
            'id': 'r$r',
            'rating': r,
            'comment': 'Комментарий $r',
            'masterName': 'Алия',
          },
      ],
      'total': ratings.length,
    };

void main() {
  testWidgets('shows the computed ratings; a master without reviews has none',
      (tester) async {
    final urls = <String>[];
    final api = _api(MockClient((r) async {
      urls.add('${r.method} ${r.url.path}?${r.url.query}');
      return r.url.path.endsWith('/summary')
          ? _json(_summary)
          : _json(_page([5, 4]));
    }));
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    expect(find.text('★ 4.5 · 2 reviews'), findsOneWidget);
    expect(find.text('★ 4.5 (2)'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('Комментарий 5'), findsOneWidget);
    expect(urls.any((u) => u.contains('/partners/p1/home-services/reviews')),
        isTrue);
  });

  testWidgets('rating and master filters go to the server', (tester) async {
    final urls = <String>[];
    final api = _api(MockClient((r) async {
      urls.add(r.url.toString());
      return r.url.path.endsWith('/summary')
          ? _json(_summary)
          : _json(_page(r.url.query.contains('rating=1') ? [1] : [5, 4]));
    }));
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('rating-1')));
    await tester.pumpAndSettle();
    expect(urls.last, contains('rating=1'));
    expect(find.text('Комментарий 1'), findsOneWidget);
    expect(find.text('Комментарий 5'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('master-m1')));
    await tester.pumpAndSettle();
    expect(urls.last, allOf(contains('rating=1'), contains('masterId=m1')));
  });

  testWidgets('no reviews: honest empty state, no invented rating',
      (tester) async {
    final api = _api(MockClient((r) async => r.url.path.endsWith('/summary')
        ? _json({
            'organization': {'rating': null, 'count': 0},
            'masters': [],
          })
        : _json(_page([]))));
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    expect(find.text('No reviews yet'), findsOneWidget);
    expect(find.text('No reviews'), findsOneWidget);
  });

  testWidgets('a complaint needs a reason and goes to the server',
      (tester) async {
    final posts = <String, Object?>{};
    final api = _api(MockClient((r) async {
      if (r.method == 'POST') {
        posts[r.url.path] = jsonDecode(r.body);
        return _json({'id': 'c1', 'status': 'OPEN'}, 201);
      }
      return r.url.path.endsWith('/summary')
          ? _json(_summary)
          : _json(_page([1]));
    }));
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('complain-r1')));
    await tester.pumpAndSettle();
    final send = find.byKey(const ValueKey('send-complaint'));
    expect(tester.widget<FilledButton>(send).onPressed, isNull);
    await tester.enterText(
        find.byKey(const ValueKey('complaint-reason')), 'Оскорбление');
    await tester.pump();
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(
      posts['/api/v1/partner/partners/p1/home-services/reviews/r1/complaint'],
      {'reason': 'Оскорбление'},
    );
  });

  testWidgets('a read-only role sees no complaint button', (tester) async {
    final api = _api(MockClient((r) async =>
        r.url.path.endsWith('/summary') ? _json(_summary) : _json(_page([1]))));
    await tester.pumpWidget(_app(api, canComplain: false));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('complain-r1')), findsNothing);
  });

  testWidgets('a failed load offers a retry', (tester) async {
    final api = _api(MockClient((r) async => _json({'code': 'X'}, 500)));
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
  });
}
