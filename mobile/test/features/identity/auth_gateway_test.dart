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
}
