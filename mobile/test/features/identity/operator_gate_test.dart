import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_localization/kunde_localizations.dart';
import 'package:kunde_auth/auth_repository.dart';
import 'package:kunde_operator/operator_gate.dart';

class _Vault implements TokenVault {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async => this.value = value;
  @override
  Future<void> clear() async => value = null;
}

class _Gateway implements OAuthGateway {
  @override
  Future<AuthTokens> login({bool register = false}) async =>
      throw IdentityUnavailable();
  @override
  Future<AuthTokens> refresh(String token) async => AuthTokens('access',
      'refresh', 'id', DateTime.now().add(const Duration(minutes: 5)));
  @override
  Future<void> logout(String? token) async {}
}

/// An indeterminate progress bar never settles and the repository awaits real asynchronous work: alternate frames with
/// short real delays for a bounded time.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late AuthRepository auth;
  var profileStatus = 200;

  setUp(() {
    profileStatus = 200;
    auth = AuthRepository(
      gateway: _Gateway(),
      vault: _Vault(),
      apiBase: Uri.parse('https://api.example.test/api/v1/'),
      client: MockClient((request) async => profileStatus == 200
          ? http.Response(
              jsonEncode({
                'id': 'synthetic',
                'displayName': 'Op',
                'preferredLanguage': 'en',
                'version': 0
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'})
          : http.Response('{}', profileStatus)),
    );
  });

  tearDown(() => auth.dispose());

  Future<void> pump(WidgetTester tester, {ValueChanged<Locale>? onLocale}) =>
      tester.pumpWidget(MaterialApp(
        localizationsDelegates: KundeLocalizations.localizationsDelegates,
        supportedLocales: KundeLocalizations.supportedLocales,
        home: OperatorGate(
          auth: auth,
          onLocale: onLocale ?? (_) {},
          authorizedHome: (_) => const Text('operator-home'),
        ),
      ));

  testWidgets(
      'shows the protected home only for a signed-in user with a loaded profile and applies the language',
      (tester) async {
    await tester.runAsync(() => auth.signIn(AuthTokens('access', 'refresh',
        'id', DateTime.now().add(const Duration(minutes: 5)))));
    Locale? applied;
    await pump(tester, onLocale: (l) => applied = l);
    await settle(tester);
    expect(find.text('operator-home'), findsOneWidget);
    expect(applied, const Locale('en'));
  });

  testWidgets('does not build protected content without a session',
      (tester) async {
    await pump(tester);
    await settle(tester);
    expect(find.text('operator-home'), findsNothing);
    expect(find.text('KUNDE'), findsOneWidget);
  });

  testWidgets(
      'a failing profile keeps protected content hidden and offers a retry',
      (tester) async {
    profileStatus = 500;
    await tester.runAsync(() => auth.signIn(AuthTokens('access', 'refresh',
        'id', DateTime.now().add(const Duration(minutes: 5)))));
    await pump(tester);
    await settle(tester);
    expect(find.text('operator-home'), findsNothing);
    expect(find.byType(FilledButton), findsOneWidget);
  });
}
