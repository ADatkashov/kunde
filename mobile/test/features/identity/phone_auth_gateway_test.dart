import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_mobile/features/identity/auth_repository.dart';
import 'package:kunde_mobile/features/identity/phone_auth_gateway.dart';

PhoneAuthGateway gatewayFor(
        Future<http.Response> Function(http.Request) handler) =>
    PhoneAuthGateway(
        apiBase: Uri.parse('https://api.example.test/api/v1/'),
        client: MockClient(handler));

const _tokens =
    '{"accessToken":"a","refreshToken":"r","tokenType":"Bearer","expiresIn":900,"refreshExpiresIn":2592000}';

void main() {
  test('requestOtp posts the E.164 number and reads the cooldown', () async {
    final gateway = gatewayFor((request) async {
      expect(request.url.path, '/api/v1/auth/otp/request');
      expect(jsonDecode(request.body), {'phone': '+77000000001'});
      return http.Response(
          '{"expiresInSeconds":300,"resendAfterSeconds":30}', 202);
    });
    final challenge = await gateway.requestOtp('+77000000001');
    expect(challenge.resendAfterSeconds, 30);
  });

  test('requestOtp maps failures without leaking server detail', () async {
    for (final entry in {
      400: PhoneAuthFailure.invalidPhone,
      429: PhoneAuthFailure.rateLimited,
      503: PhoneAuthFailure.unavailable,
      500: PhoneAuthFailure.unavailable,
    }.entries) {
      final gateway = gatewayFor((_) async => http.Response('{}', entry.key));
      await expectLater(
          gateway.requestOtp('+77000000001'),
          throwsA(isA<PhoneAuthException>()
              .having((e) => e.failure, 'failure', entry.value)));
    }
    final offline =
        gatewayFor((_) async => throw http.ClientException('offline'));
    await expectLater(
        offline.requestOtp('+77000000001'),
        throwsA(isA<PhoneAuthException>()
            .having((e) => e.failure, 'failure', PhoneAuthFailure.network)));
  });

  test('verifyOtp returns tokens and rejects wrong codes', () async {
    final ok = gatewayFor((request) async {
      expect(request.url.path, '/api/v1/auth/otp/verify');
      expect(jsonDecode(request.body),
          {'phone': '+77000000001', 'code': '123456'});
      return http.Response(_tokens, 200);
    });
    final tokens = await ok.verifyOtp('+77000000001', '123456');
    expect(tokens.access, 'a');
    expect(tokens.refresh, 'r');
    expect(
        tokens.expires.isAfter(DateTime.now().add(const Duration(minutes: 10))),
        true);

    final bad =
        gatewayFor((_) async => http.Response('{"code":"INVALID_CODE"}', 401));
    await expectLater(
        bad.verifyOtp('+77000000001', '000000'),
        throwsA(isA<PhoneAuthException>().having(
            (e) => e.failure, 'failure', PhoneAuthFailure.invalidCode)));
    final malformed =
        gatewayFor((_) async => http.Response('{"accessToken":"a"}', 200));
    await expectLater(malformed.verifyOtp('+77000000001', '123456'),
        throwsA(isA<PhoneAuthException>()));
  });

  test('refresh separates revoked sessions from outages', () async {
    final ok = gatewayFor((request) async {
      expect(jsonDecode(request.body), {'refreshToken': 'old'});
      return http.Response(_tokens, 200);
    });
    expect((await ok.refresh('old')).refresh, 'r');
    await expectLater(
        gatewayFor((_) async => http.Response('{}', 401)).refresh('old'),
        throwsA(isA<SessionExpired>()));
    await expectLater(
        gatewayFor((_) async => http.Response('{}', 503)).refresh('old'),
        throwsA(isA<IdentityUnavailable>()));
    await expectLater(
        gatewayFor((_) async => throw http.ClientException('offline'))
            .refresh('old'),
        throwsA(isA<IdentityUnavailable>()));
  });

  test('revoke succeeds only on 204', () async {
    await gatewayFor((request) async {
      expect(request.url.path, '/api/v1/auth/logout');
      return http.Response('', 204);
    }).revoke('r');
    await expectLater(
        gatewayFor((_) async => http.Response('{}', 503)).revoke('r'),
        throwsA(isA<IdentityUnavailable>()));
  });
}
