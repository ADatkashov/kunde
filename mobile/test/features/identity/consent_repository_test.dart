import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_mobile/features/identity/auth_repository.dart';

class TestVault implements TokenVault {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async {}
  @override
  Future<void> clear() async {}
}

class TestGateway implements OAuthGateway {
  @override
  Future<AuthTokens> login({bool register = false}) async => AuthTokens(
      'test-access', 'test-refresh', null, DateTime.now().add(const Duration(minutes: 5)));
  @override
  Future<AuthTokens> refresh(String refreshToken) async => login();
  @override
  Future<void> logout(String? idToken) async {}
}

void main() {
  const policy = '11111111-2222-3333-4444-555555555555';
  test('consent client scopes requests to current bearer and correct methods', () async {
    final methods = <String>[];
    final auth = AuthRepository(
      gateway: TestGateway(),
      vault: TestVault(),
      apiBase: Uri.parse('https://api.example.test/api/v1/'),
      client: MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer test-access');
        methods.add('${request.method} ${request.url.path}');
        if (request.method == 'GET') {
          return http.Response('[{"policyId":"$policy","granted":false}]', 200);
        }
        return http.Response('{"policyId":"$policy","granted":true}', 200);
      }),
    );
    addTearDown(auth.dispose);
    await auth.login();
    expect((await auth.consents()).single['granted'], false);
    expect((await auth.setConsent(policy, true))['granted'], true);
    await auth.setConsent(policy, false);
    expect(methods, [
      'GET /api/v1/me/consents',
      'PUT /api/v1/me/consents/$policy',
      'DELETE /api/v1/me/consents/$policy'
    ]);
  });

  test('invalid policy ID never causes network request', () async {
    final auth = AuthRepository(
      gateway: TestGateway(),
      vault: TestVault(),
      apiBase: Uri.parse('https://api.example.test/api/v1/'),
      client: MockClient((_) async => throw StateError('Network called')),
    );
    addTearDown(auth.dispose);
    await auth.login();
    await expectLater(auth.setConsent('../other', true), throwsArgumentError);
  });

  test('401 on consent request invalidates the local session', () async {
    final auth = AuthRepository(
      gateway: TestGateway(),
      vault: TestVault(),
      apiBase: Uri.parse('https://api.example.test/api/v1/'),
      client: MockClient((_) async => http.Response('{}', 401)),
    );
    addTearDown(auth.dispose);
    await auth.login();
    await expectLater(auth.consents(), throwsA(isA<SessionExpired>()));
    expect(auth.authenticated, false);
  });
}
