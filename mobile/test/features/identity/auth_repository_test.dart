import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_mobile/features/identity/auth_repository.dart';

class Vault implements TokenVault {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String v) async {
    value = v;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

class Gateway implements OAuthGateway {
  int refreshes = 0;
  bool fail = false;
  bool logoutFail = false;
  @override
  Future<AuthTokens> login({bool register = false}) async => AuthTokens('old',
      'refresh-old', 'id', DateTime.now().subtract(const Duration(seconds: 1)));
  @override
  Future<AuthTokens> refresh(String refreshToken) async {
    refreshes++;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (fail) throw SessionExpired();
    return AuthTokens('new', 'refresh-new', 'id-new',
        DateTime.now().add(const Duration(minutes: 5)));
  }

  @override
  Future<void> logout(String? idToken) async {
    if (logoutFail) throw IdentityUnavailable();
  }
}

void main() {
  late Gateway gateway;
  late Vault vault;
  late AuthRepository auth;
  setUp(() {
    gateway = Gateway();
    vault = Vault();
    auth = AuthRepository(
        gateway: gateway,
        vault: vault,
        apiBase: Uri.parse('https://api.example.test/api/v1/'));
  });
  tearDown(() => auth.dispose());
  test('parallel protected requests rotate once and replace persistent set',
      () async {
    await auth.login();
    expect(await Future.wait(List.generate(12, (_) => auth.accessToken())),
        everyElement('new'));
    expect(gateway.refreshes, 1);
    final stored = jsonDecode(vault.value!) as Map<String, dynamic>;
    expect(stored['refresh'], 'refresh-new');
    expect(stored.containsKey('access'), false);
  });
  test('refresh rejection clears authentication and persistent tokens',
      () async {
    await auth.login();
    gateway.fail = true;
    await expectLater(auth.accessToken(), throwsA(isA<SessionExpired>()));
    expect(auth.authenticated, false);
    expect(auth.expired, true);
    expect(vault.value, null);
  });
  test('logout follows in-flight refresh and cannot restore logged-out state',
      () async {
    await auth.login();
    final pending = auth.accessToken();
    final logout = auth.logout();
    await pending;
    expect(await logout, true);
    expect(auth.authenticated, false);
    expect(vault.value, null);
  });
  test('offline provider logout still clears local state', () async {
    await auth.login();
    gateway.logoutFail = true;
    expect(await auth.logout(), false);
    expect(auth.authenticated, false);
    expect(vault.value, null);
  });
  test('restore rotates and malformed storage fails closed', () async {
    vault.value = jsonEncode({'refresh': 'saved'});
    await auth.restore();
    expect(auth.authenticated, true);
    expect(gateway.refreshes, 1);
    vault.value = 'malformed';
    await auth.restore();
    expect(auth.authenticated, false);
    expect(vault.value, null);
  });
}
