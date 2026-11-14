import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_mobile/features/home/data/kunde_api.dart';
import 'package:kunde_mobile/features/identity/auth_repository.dart';
import 'package:kunde_mobile/features/identity/consent_panel.dart';
import 'package:kunde_mobile/features/identity/phone_auth_gateway.dart';
import 'package:kunde_mobile/features/identity/phone_login_flow.dart';
import 'package:kunde_mobile/main.dart';

class _Vault implements TokenVault {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String v) async => value = v;
  @override
  Future<void> clear() async => value = null;
}

void main() {
  late _Vault vault;
  late AuthRepository auth;
  late KundeApi api;
  var created = false;
  late List<String> calls;
  var verifyStatus = 200;
  var refreshStatus = 200;
  var logoutStatus = 204;
  var rotation = 0;
  String? lastLogoutBody;

  Map<String, dynamic> tokens() => {
        'accessToken': 'access-${++rotation}',
        'refreshToken': 'refresh-$rotation',
        'tokenType': 'Bearer',
        'expiresIn': 900,
        'refreshExpiresIn': 2592000,
      };

  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path.replaceFirst('/api/v1/', '');
    calls.add('${request.method} $path');
    switch (path) {
      case 'auth/otp/request':
        return http.Response(
            '{"expiresInSeconds":300,"resendAfterSeconds":30}', 202);
      case 'auth/otp/verify':
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['phone'] != '+77000000001') return http.Response('{}', 400);
        if (verifyStatus != 200 || body['code'] != '123456') {
          return http.Response('{"code":"INVALID_CODE"}',
              verifyStatus == 200 ? 401 : verifyStatus);
        }
        return http.Response(jsonEncode(tokens()), 200);
      case 'auth/token/refresh':
        return refreshStatus == 200
            ? http.Response(jsonEncode(tokens()), 200)
            : http.Response('{}', refreshStatus);
      case 'auth/logout':
        lastLogoutBody = request.body;
        return http.Response('', logoutStatus);
      case 'me':
        if (!(request.headers['Authorization'] ?? '')
            .startsWith('Bearer access-')) {
          return http.Response('{}', 401);
        }
        return http.Response(
            jsonEncode({
              'id': 'synthetic',
              'displayName': 'Aruzhan',
              'preferredLanguage': 'en',
              'version': 0
            }),
            200);
      case 'me/addresses':
        return http.Response(
            jsonEncode([
              {
                'id': '11111111-2222-3333-4444-555555555555',
                'label': 'Home',
                'formattedAddress': 'Synthetic street 1',
                'version': 0,
                'serviceable': false
              }
            ]),
            200);
      case 'me/consents':
        return http.Response('[]', 200);
      case 'me/support/cases':
        return http.Response('[]', 200);
    }
    return http.Response('{}', 404);
  }

  Future<void> start(WidgetTester tester, {bool devHint = false}) async {
    calls = [];
    created = true;
    vault = _Vault();
    verifyStatus = 200;
    refreshStatus = 200;
    logoutStatus = 204;
    rotation = 0;
    lastLogoutBody = null;
    final base = Uri.parse('https://api.example.test/api/v1/');
    final client = MockClient(handle);
    auth = AuthRepository(
        gateway: PhoneAuthGateway(apiBase: base, client: client),
        vault: vault,
        apiBase: base,
        client: client);
    api = KundeApi(
        baseUri: base,
        client: MockClient((_) async => http.Response(
            jsonEncode({
              'releaseStage': 'FOUNDATION',
              'marketplaceEnabled': false,
              'oidcIssuerConfigured': false,
              'aiEnabled': false,
            }),
            200)));
    await tester
        .pumpWidget(KundeApp(api: api, auth: auth, devOtpHint: devHint));
    await tester.pumpAndSettle();
  }

  tearDown(() {
    if (!created) return;
    created = false;
    auth.dispose();
    api.close();
  });

  Future<void> enterPhone(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('phone-field')), '7000000001');
    await tester.pump();
    await tester.tap(find.byKey(const Key('get-code')));
    await tester.pumpAndSettle();
  }

  testWidgets('phone, OTP, profile, consents and addresses', (tester) async {
    await start(tester, devHint: true);
    expect(find.text('Sign in with your phone'), findsOneWidget);
    // The button stays disabled until ten digits are present.
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('get-code')))
            .onPressed,
        isNull);
    await enterPhone(tester);
    expect(find.text('Enter the code'), findsOneWidget);
    expect(find.text('Code sent to +7 700 000 00 01'), findsOneWidget);
    expect(find.byKey(const Key('dev-otp-hint')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('otp-field')), '123456');
    await tester.pumpAndSettle();
    // Automatic transition into the app after a correct code.
    expect(find.text('Sign in with your phone'), findsNothing);
    expect(find.text('Home'), findsWidgets);
    expect(
        calls,
        containsAllInOrder(
            ['POST auth/otp/request', 'POST auth/otp/verify', 'GET me']));
    expect(jsonDecode(vault.value!)['refresh'], 'refresh-1');

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Aruzhan'), findsOneWidget);
    await tester.scrollUntilVisible(find.byType(ConsentPanel), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(calls, contains('GET me/addresses'));
    expect(calls, contains('GET me/consents'));
  });

  testWidgets('DEV test code hint is hidden unless explicitly enabled',
      (tester) async {
    await start(tester);
    await enterPhone(tester);
    expect(find.byKey(const Key('dev-otp-hint')), findsNothing);
    expect(find.textContaining('123456'), findsNothing);
  });

  testWidgets('wrong code shows an error and allows another attempt',
      (tester) async {
    await start(tester);
    await enterPhone(tester);
    await tester.enterText(find.byKey(const Key('otp-field')), '000000');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('phone-auth-error')), findsOneWidget);
    expect(find.textContaining('wrong or expired'), findsOneWidget);
    expect(auth.authenticated, false);
    await tester.enterText(find.byKey(const Key('otp-field')), '123456');
    await tester.pumpAndSettle();
    expect(auth.authenticated, true);
  });

  testWidgets('phone number is validated and can be changed', (tester) async {
    await start(tester);
    await tester.enterText(find.byKey(const Key('phone-field')), '700');
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('get-code')))
            .onPressed,
        isNull);
    await tester.enterText(find.byKey(const Key('phone-field')), '7000000001');
    await tester.pump();
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('phone-field')))
            .controller!
            .text,
        '700 000 00 01');
    await tester.tap(find.byKey(const Key('get-code')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('change-number')));
    await tester.pumpAndSettle();
    expect(find.text('Sign in with your phone'), findsOneWidget);
  });

  testWidgets('resend is blocked during the cooldown', (tester) async {
    await start(tester);
    await enterPhone(tester);
    expect(
        tester
            .widget<TextButton>(find.byKey(const Key('resend-code')))
            .onPressed,
        isNull);
    expect(find.text('Resend code in 30s'), findsOneWidget);
    await tester.pump(const Duration(seconds: 31));
    expect(
        tester
            .widget<TextButton>(find.byKey(const Key('resend-code')))
            .onPressed,
        isNotNull);
  });

  testWidgets('stored session is restored through refresh', (tester) async {
    calls = [];
    created = true;
    vault = _Vault();
    rotation = 10;
    verifyStatus = 200;
    refreshStatus = 200;
    final base = Uri.parse('https://api.example.test/api/v1/');
    final client = MockClient(handle);
    vault.value = jsonEncode({
      'issuerVersion': 2,
      'context': base.toString(),
      'refresh': 'saved-refresh'
    });
    auth = AuthRepository(
        gateway: PhoneAuthGateway(apiBase: base, client: client),
        vault: vault,
        apiBase: base,
        client: client);
    api = KundeApi(
        baseUri: base,
        client: MockClient((_) async => http.Response('{}', 200)));
    await tester.pumpWidget(KundeApp(api: api, auth: auth));
    await tester.pumpAndSettle();
    expect(calls.first, 'POST auth/token/refresh');
    expect(auth.authenticated, true);
    expect(find.text('Sign in with your phone'), findsNothing);
    expect(jsonDecode(vault.value!)['refresh'], 'refresh-11');
  });

  testWidgets('revoked stored session returns to phone sign-in',
      (tester) async {
    calls = [];
    created = true;
    vault = _Vault();
    refreshStatus = 401;
    final base = Uri.parse('https://api.example.test/api/v1/');
    final client = MockClient(handle);
    vault.value = jsonEncode(
        {'issuerVersion': 2, 'context': base.toString(), 'refresh': 'revoked'});
    auth = AuthRepository(
        gateway: PhoneAuthGateway(apiBase: base, client: client),
        vault: vault,
        apiBase: base,
        client: client);
    api = KundeApi(
        baseUri: base,
        client: MockClient((_) async => http.Response('{}', 200)));
    await tester.pumpWidget(KundeApp(api: api, auth: auth));
    await tester.pumpAndSettle();
    expect(auth.authenticated, false);
    expect(vault.value, isNull);
    expect(find.text('Sign in with your phone'), findsOneWidget);
  });

  testWidgets('logout revokes the server session and clears the vault',
      (tester) async {
    await start(tester);
    await enterPhone(tester);
    await tester.enterText(find.byKey(const Key('otp-field')), '123456');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(jsonDecode(lastLogoutBody!), {'refreshToken': 'refresh-1'});
    expect(vault.value, isNull);
    expect(find.text('Sign in with your phone'), findsOneWidget);
  });

  testWidgets('failed server logout still signs out locally and says so',
      (tester) async {
    await start(tester);
    await enterPhone(tester);
    await tester.enterText(find.byKey(const Key('otp-field')), '123456');
    await tester.pumpAndSettle();
    logoutStatus = 503;
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(vault.value, isNull);
    expect(find.textContaining('will expire on its own'), findsOneWidget);
  });

  test('national phone formatter groups digits and strips prefixes', () {
    expect(NationalPhoneFormatter.format('7000000001'), '700 000 00 01');
    expect(NationalPhoneFormatter.format('70'), '70');
    final formatter = NationalPhoneFormatter();
    final value = formatter.formatEditUpdate(TextEditingValue.empty,
        const TextEditingValue(text: '+7 700 000 00 01'));
    expect(value.text, '700 000 00 01');
    final long = formatter.formatEditUpdate(
        TextEditingValue.empty, const TextEditingValue(text: '87000000001'));
    expect(long.text, '700 000 00 01');
  });
}
