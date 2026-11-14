import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_mobile/features/identity/auth_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('crossingthestreams.io/flutter_appauth');
  late List<MethodCall> calls;
  String? error;
  bool unstructured = false;
  setUp(() {
    calls = [];
    error = null;
    unstructured = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (unstructured) {
        throw PlatformException(code: "transport_failed");
      }
      if (error != null) {
        throw PlatformException(
            code: 'token_failed', details: {'error': error});
      }
      return {
        'accessToken': 'access',
        'refreshToken': 'refresh',
        'idToken': 'id',
        'accessTokenExpirationTime': DateTime.now()
            .add(const Duration(minutes: 5))
            .millisecondsSinceEpoch
      };
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));
  AppAuthGateway gateway(
          [String issuer = 'https://identity.example.test/realms/kunde']) =>
      AppAuthGateway(issuer: issuer, clientId: 'kunde-consumer');
  test('login uses native code exchange, exact issuer, callback and scopes',
      () async {
    await gateway().login();
    final call = calls.single;
    expect(call.method, 'authorizeAndExchangeCode');
    final args = call.arguments as Map;
    expect(args['issuer'], 'https://identity.example.test/realms/kunde');
    expect(args['clientId'], 'kunde-consumer');
    expect(args['redirectUrl'], 'com.kunde.mobile:/oauth2redirect');
    expect(
        args['scopes'], containsAll(['openid', 'profile', 'kunde.consumer']));
    expect(args['clientSecret'], isNull);
    expect(args['allowInsecureConnections'], false);
  });
  test(
      'registration uses Keycloak registration endpoint with native code exchange',
      () async {
    await gateway().login(register: true);
    final args = calls.single.arguments as Map;
    final config = args['serviceConfiguration'] as Map;
    expect(config['authorizationEndpoint'],
        'https://identity.example.test/realms/kunde/protocol/openid-connect/registrations');
    expect(config['tokenEndpoint'],
        'https://identity.example.test/realms/kunde/protocol/openid-connect/token');
    expect(args['additionalParameters'], isNull);
    expect(calls.single.method, 'authorizeAndExchangeCode');
  });
  test(
      'refresh rejection and temporary provider errors have different recovery',
      () async {
    error = 'invalid_grant';
    await expectLater(
        gateway().refresh('saved'), throwsA(isA<SessionExpired>()));
    error = 'temporarily_unavailable';
    await expectLater(
        gateway().refresh('saved'), throwsA(isA<IdentityUnavailable>()));
  });
  test('logout passes id token hint and exact callback to native browser',
      () async {
    await gateway().logout('id');
    expect(calls.single.method, 'endSession');
    expect((calls.single.arguments as Map)['idTokenHint'], 'id');
    expect((calls.single.arguments as Map)['postLogoutRedirectUrl'],
        'com.kunde.mobile:/oauth2redirect');
  });
  test('unsafe issuer is rejected before calling native code', () async {
    await expectLater(gateway('http://identity.example.test').login(),
        throwsA(isA<IdentityUnavailable>()));
    await expectLater(
        gateway('https://identity.example.test?redirect=evil').login(),
        throwsA(isA<IdentityUnavailable>()));
    expect(calls, isEmpty);
  });
  test('unstructured native transport failure remains recoverable', () async {
    unstructured = true;
    await expectLater(
        gateway().refresh('saved'), throwsA(isA<IdentityUnavailable>()));
  });
  test('trailing slash is normalized for registration endpoints', () async {
    await gateway('https://identity.example.test/realms/kunde/')
        .login(register: true);
    final config =
        (calls.single.arguments as Map)['serviceConfiguration'] as Map;
    expect(config['authorizationEndpoint'],
        'https://identity.example.test/realms/kunde/protocol/openid-connect/registrations');
  });
  test('ZITADEL profile uses discovery, prompt=create and configured scopes',
      () async {
    final zitadel = AppAuthGateway(
        issuer: 'https://kunde-dev.zitadel.cloud',
        clientId: '123456789',
        provider: 'zitadel',
        scopes: AppAuthGateway.parseScopes(
            'openid profile offline_access urn:zitadel:iam:org:project:id:42:aud'));
    await zitadel.login(register: true);
    final args = calls.single.arguments as Map;
    expect(args['issuer'], 'https://kunde-dev.zitadel.cloud');
    expect(args['serviceConfiguration'], isNull);
    expect(args['additionalParameters'], {'prompt': 'create'});
    expect(
        args['scopes'],
        containsAll([
          'openid',
          'offline_access',
          'urn:zitadel:iam:org:project:id:42:aud'
        ]));
    expect(args['scopes'], isNot(contains('kunde.consumer')));
    await zitadel.login();
    expect((calls.last.arguments as Map)['additionalParameters'], isNull);
    await zitadel.refresh('saved');
    expect((calls.last.arguments as Map)['scopes'], contains('offline_access'));
  });
  test('unknown provider is rejected and empty scopes keep the default',
      () async {
    await expectLater(
        AppAuthGateway(
                issuer: 'https://identity.example.test',
                clientId: 'c',
                provider: 'other')
            .login(),
        throwsA(isA<IdentityUnavailable>()));
    expect(calls, isEmpty);
    expect(AppAuthGateway.parseScopes('  '), isNull);
    expect(AppAuthGateway.parseScopes('openid,profile'), ['openid', 'profile']);
  });
}
