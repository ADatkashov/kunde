import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_mobile/features/education/education_enrollment_screen.dart';
import 'package:kunde_mobile/features/home/data/kunde_api.dart';
import 'package:kunde_mobile/features/identity/auth_repository.dart';

class _Vault implements TokenVault {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async {}
  @override
  Future<void> clear() async {}
}

class _Gateway implements OAuthGateway {
  @override
  Future<AuthTokens> login({bool register = false}) async => AuthTokens(
      'access', 'refresh', null, DateTime.now().add(const Duration(hours: 1)));
  @override
  Future<AuthTokens> refresh(String refreshToken) => login();
  @override
  Future<void> logout(String? idToken) async {}
}

void main() {
  testWidgets('cohort → test card → text lesson → completion code',
      (tester) async {
    final endpoint = Uri.parse('https://api.example.test/api/v1/');
    final gateway = _Gateway();
    final auth =
        AuthRepository(gateway: gateway, vault: _Vault(), apiBase: endpoint);
    await auth.signIn(await gateway.login());
    addTearDown(auth.dispose);

    String? key;
    var complete = false;
    final api = KundeApi(
        baseUri: endpoint,
        client: MockClient((request) async {
          http.Response reply(Object data, [int status = 200]) =>
              http.Response(jsonEncode(data), status,
                  headers: {'content-type': 'application/json'});
          if (request.url.path.endsWith('/cohorts')) {
            return reply([
              {
                'id': 'cohort',
                'format': 'ONLINE_RECORDED',
                'priceMinor': 10000,
                'remaining': 1
              }
            ]);
          }
          expect(request.headers['authorization'], 'Bearer access');
          if (request.method == 'POST') {
            expect(jsonDecode(request.body), {
              'cohortId': 'cohort',
              'expectedPriceMinor': 10000,
              'paymentMethod': 'TEST_CARD'
            });
            final previous = key;
            key = request.headers['idempotency-key'];
            expect(key, isNotNull);
            if (previous == null) return reply({'code': 'UNAVAILABLE'}, 503);
            expect(key, previous);
            return reply({'id': 'enrollment'}, 201);
          }
          if (request.method == 'PUT') {
            expect(request.url.path,
                endsWith('/enrollments/enrollment/lessons/1/1/completion'));
            complete = true;
          }
          return reply({
            'enrollment': {
              'title': 'Python',
              if (complete) 'certificateCode': 'verified-demo-code'
            },
            'lessons': [
              {
                'modulePosition': 1,
                'lessonPosition': 1,
                'title': 'Variables',
                'content': 'A variable stores a value.',
                'completed': complete
              },
            ],
          });
        }));
    addTearDown(api.close);

    await tester.pumpWidget(MaterialApp(
      home: EducationEnrollmentScreen(api: api, auth: auth, courseId: 'python'),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recorded'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pay with TEST_CARD'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Enrollment was not confirmed'), findsOneWidget);
    await tester.tap(find.text('Pay with TEST_CARD'));
    await tester.pumpAndSettle();
    expect(find.text('Test payment captured'), findsOneWidget);
    await tester.tap(find.text('Variables'));
    await tester.pumpAndSettle();
    expect(find.text('A variable stores a value.'), findsOneWidget);
    await tester.tap(find.text('Complete lesson'));
    await tester.pumpAndSettle();
    expect(find.text('verified-demo-code'), findsOneWidget);
  });
}
