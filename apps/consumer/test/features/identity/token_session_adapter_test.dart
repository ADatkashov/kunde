import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_auth/auth_repository.dart';

/// Consumer/operator adapter of the shared token-session core (ADR-024).
class _Vault implements TokenVault {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String v) async => value = v;
  @override
  Future<void> clear() async => value = null;
}

class _Gateway implements OAuthGateway, SessionRevoker {
  int refreshes = 0;
  final List<String> used = [];
  final List<String> revoked = [];
  Object? failure;
  int minutes = 5;
  @override
  Future<AuthTokens> login({bool register = false}) async =>
      throw IdentityUnavailable();
  @override
  Future<AuthTokens> refresh(String refreshToken) async {
    refreshes++;
    used.add(refreshToken);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (failure != null) throw failure!;
    return AuthTokens('access-$refreshes', 'refresh-$refreshes', null,
        DateTime.now().add(Duration(minutes: minutes)));
  }

  @override
  Future<void> logout(String? idToken) async {}
  @override
  Future<void> revoke(String refreshToken) async => revoked.add(refreshToken);
}

final _base = Uri.parse('https://api.example.test/api/v1/');

AuthTokens _expiring() => AuthTokens('stale', 'refresh-0', 'id-0',
    DateTime.now().subtract(const Duration(seconds: 1)));

void main() {
  late _Gateway gateway;
  late _Vault vault;
  late List<http.Request> requests;
  late AuthRepository auth;

  AuthRepository build({TokenVault? v, int status = 200}) => AuthRepository(
        gateway: gateway,
        vault: v ?? vault,
        apiBase: _base,
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(jsonEncode({'ok': true}), status,
              headers: {'content-type': 'application/json'});
        }),
      );

  setUp(() {
    gateway = _Gateway();
    vault = _Vault();
    requests = [];
    auth = build();
  });
  tearDown(() => auth.dispose());

  test(
      'many simultaneous requests with an expired token spend the rotating refresh token once',
      () async {
    await auth.signIn(_expiring());
    final tokens =
        await Future.wait(List.generate(8, (_) => auth.accessToken()));
    expect(tokens.toSet(), {'access-1'});
    expect(gateway.used, ['refresh-0']);
    expect(jsonDecode(vault.value!)['refresh'], 'refresh-1');
  });

  test(
      'restore after a restart rotates the stored refresh token and keeps the id token',
      () async {
    await auth.signIn(_expiring());
    final restarted = build();
    await restarted.restore();
    expect(restarted.authenticated, isTrue);
    expect(gateway.used, ['refresh-0']);
    final stored = jsonDecode(vault.value!) as Map<String, dynamic>;
    expect(stored['refresh'], 'refresh-1');
    expect(stored['id'], 'id-0');
    restarted.dispose();
  });

  test(
      'an invalid refresh token clears the session and marks it expired; access is then refused',
      () async {
    await auth.signIn(_expiring());
    gateway.failure = SessionExpired();
    await expectLater(auth.accessToken(), throwsA(isA<SessionExpired>()));
    expect(auth.authenticated, isFalse);
    expect(auth.expired, isTrue);
    expect(vault.value, isNull);
    await expectLater(auth.accessToken(), throwsA(isA<SessionExpired>()));
  });

  test('a network failure keeps the session and the stored refresh token',
      () async {
    await auth.signIn(_expiring());
    gateway.failure = IdentityUnavailable();
    await expectLater(auth.accessToken(), throwsA(isA<IdentityUnavailable>()));
    expect(auth.authenticated, isTrue);
    expect(jsonDecode(vault.value!)['refresh'], 'refresh-0');
    gateway.failure = null;
    expect(await auth.accessToken(), 'access-2');
  });

  test(
      'phone-OTP logout clears local state first and revokes the refresh token on the server',
      () async {
    await auth.signIn(_expiring());
    expect(await auth.logout(), isTrue);
    expect(auth.authenticated, isFalse);
    expect(vault.value, isNull);
    expect(gateway.revoked, ['refresh-0']);
  });

  test('sessions of different roles are isolated by their storage key',
      () async {
    final storage = <String, String>{};
    TokenVault keyed(String key) => _KeyedVault(storage, key);
    final consumer = build(v: keyed('kunde.consumer.session.v1'));
    final executor = build(v: keyed('kunde.executor.session.v1'));
    await consumer.signIn(_expiring());
    await executor.restore();
    expect(executor.authenticated, isFalse);
    expect(storage.keys, ['kunde.consumer.session.v1']);
    await executor.signIn(AuthTokens('a', 'refresh-executor', null,
        DateTime.now().add(const Duration(minutes: 5))));
    await consumer.logout();
    expect(storage.keys, ['kunde.executor.session.v1']);
    consumer.dispose();
    executor.dispose();
  });

  test(
      'a stored session for another API context is rejected without sending its token anywhere',
      () async {
    vault.value = jsonEncode({
      'issuerVersion': 2,
      'context': 'https://other.example/api/v1/',
      'refresh': 'foreign'
    });
    await auth.restore();
    expect(auth.authenticated, isFalse);
    expect(gateway.refreshes, 0);
    expect(vault.value, isNull);
  });

  test(
      'the bearer token is never sent outside the API: foreign origins and paths are refused',
      () async {
    await auth.signIn(AuthTokens('live', 'refresh-0', null,
        DateTime.now().add(const Duration(minutes: 5))));
    for (final path in [
      'https://evil.example/steal',
      '//evil.example/steal',
      'https://api.example.test/other/x'
    ]) {
      await expectLater(
          auth.authorizedJson('GET', path), throwsA(isA<ArgumentError>()),
          reason: path);
    }
    expect(requests, isEmpty);
    await auth.authorizedJson('GET', 'me');
    expect(requests.single.url.host, 'api.example.test');
    expect(requests.single.headers['Authorization'], 'Bearer live');
  });

  test('tokens do not leak into exception text', () async {
    await auth.signIn(AuthTokens('SECRET-ACCESS', 'SECRET-REFRESH', null,
        DateTime.now().subtract(const Duration(seconds: 1))));
    gateway.failure = SessionExpired();
    Object? failure;
    try {
      await auth.accessToken();
    } catch (e) {
      failure = e;
    }
    expect(failure.toString(), isNot(contains('SECRET')));
  });
}

class _KeyedVault implements TokenVault {
  _KeyedVault(this.storage, this.key);
  final Map<String, String> storage;
  final String key;
  @override
  Future<String?> read() async => storage[key];
  @override
  Future<void> write(String value) async => storage[key] = value;
  @override
  Future<void> clear() async => storage.remove(key);
}
