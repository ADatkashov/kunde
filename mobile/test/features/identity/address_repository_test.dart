import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_mobile/features/identity/auth_repository.dart';

class Vault implements TokenVault {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async {}
  @override
  Future<void> clear() async {}
}

class Gateway implements OAuthGateway {
  @override
  Future<AuthTokens> login({bool register = false}) async => AuthTokens(
      'access',
      'refresh',
      null,
      DateTime.now().add(const Duration(minutes: 5)));
  @override
  Future<AuthTokens> refresh(String refreshToken) async => login();
  @override
  Future<void> logout(String? idToken) async {}
}

void main() {
  const id = '11111111-2222-3333-4444-555555555555';
  test('address list/create/delete uses authenticated owner routes', () async {
    final seen = <String>[];
    final auth = AuthRepository(
      gateway: Gateway(),
      vault: Vault(),
      apiBase: Uri.parse('https://api.example.test/api/v1/'),
      client: MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer access');
        seen.add('${request.method} ${request.url}');
        if (request.method == 'GET') return http.Response('[]', 200);
        if (request.method == 'POST') {
          expect(request.body, contains('Synthetic address'));
          return http.Response('{"id":"$id","serviceable":false}', 201);
        }
        return http.Response('', 204);
      }),
    );
    addTearDown(auth.dispose);
    await auth.login();
    expect(await auth.addresses(), isEmpty);
    expect(
        (await auth.createAddress(
          label: 'Home',
          formattedAddress: 'Synthetic address',
          latitude: 43.2,
          longitude: 76.9,
        ))['serviceable'],
        false);
    await auth.deleteAddress(id, 0);
    expect(seen, [
      'GET https://api.example.test/api/v1/me/addresses',
      'POST https://api.example.test/api/v1/me/addresses',
      'DELETE https://api.example.test/api/v1/me/addresses/$id?version=0',
    ]);
  });

  test('invalid coordinates and malformed ID are rejected before network',
      () async {
    final auth = AuthRepository(
      gateway: Gateway(),
      vault: Vault(),
      apiBase: Uri.parse('https://api.example.test/api/v1/'),
      client: MockClient((_) async => throw StateError('Unexpected network')),
    );
    addTearDown(auth.dispose);
    await auth.login();
    await expectLater(
      auth.createAddress(
          label: 'Home',
          formattedAddress: 'Address',
          latitude: double.nan,
          longitude: 76.9),
      throwsArgumentError,
    );
    await expectLater(auth.deleteAddress('../other', 0), throwsArgumentError);
    await expectLater(auth.deleteAddress(id, -1), throwsArgumentError);
  });

  test('optimistic delete conflict is not treated as successful deletion',
      () async {
    final auth = AuthRepository(
      gateway: Gateway(),
      vault: Vault(),
      apiBase: Uri.parse('https://api.example.test/api/v1/'),
      client: MockClient((_) async => http.Response('{}', 409)),
    );
    addTearDown(auth.dispose);
    await auth.login();
    await expectLater(
        auth.deleteAddress(id, 2), throwsA(isA<IdentityApiError>()));
    expect(auth.authenticated, true);
  });
}
