import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_mobile/core/localization/kunde_localizations.dart';
import 'package:kunde_mobile/features/identity/auth_repository.dart';
import 'package:kunde_mobile/features/identity/consent_panel.dart';

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
        'access',
        'refresh',
        null,
        DateTime.now().add(const Duration(minutes: 5)),
      );
  @override
  Future<AuthTokens> refresh(String refreshToken) => login();
  @override
  Future<void> logout(String? idToken) async {}
}

const _sha = 'a3f1c2d4e5b60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';

Map<String, dynamic> _policy(String locale, {bool granted = false}) => {
      'policyId': '00000000-0000-0000-0000-00000000000${locale.length}$locale',
      'purpose': 'marketing',
      'policyVersion': 'v1',
      'locale': locale,
      'documentSha256': _sha,
      'granted': granted,
    };

Future<AuthRepository> _signedIn(List<Map<String, dynamic>> items) async {
  final auth = AuthRepository(
    gateway: _Gateway(),
    vault: _Vault(),
    apiBase: Uri.parse('https://api.example.test/api/v1/'),
    client: MockClient(
      (request) async => http.Response(
        jsonEncode(items),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    ),
  );
  await auth.login();
  return auth;
}

Future<void> _show(
  WidgetTester tester,
  AuthRepository auth,
  String language,
) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(language),
      supportedLocales: KundeLocalizations.supportedLocales,
      localizationsDelegates: KundeLocalizations.localizationsDelegates,
      home: Scaffold(
        body: SingleChildScrollView(child: ConsentPanel(auth: auth)),
      ),
    ),
  );
  for (var i = 0;
      i < 40 && find.byType(SwitchListTile).evaluate().isEmpty;
      i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('one switch per policy in the reader language, no text claimed',
      (tester) async {
    final auth = await _signedIn([_policy('ru'), _policy('kk'), _policy('en')]);
    addTearDown(auth.dispose);
    await _show(tester, auth, 'en');
    expect(find.byType(SwitchListTile), findsOneWidget);
    expect(find.textContaining('v1 · English'), findsOneWidget);
    expect(find.textContaining('No version in your language'), findsNothing);
    expect(find.textContaining('policy text is not available'), findsOneWidget);
    expect(find.textContaining('SHA-256: $_sha'), findsOneWidget);
  });

  testWidgets('missing language version is announced in Kazakh',
      (tester) async {
    final auth = await _signedIn([_policy('ru'), _policy('en')]);
    addTearDown(auth.dispose);
    await _show(tester, auth, 'kk');
    expect(find.byType(SwitchListTile), findsOneWidget);
    expect(find.textContaining('Құжат тілі: Русский'), findsOneWidget);
    expect(
        find.textContaining('әзірге қолданбада қолжетімсіз'), findsOneWidget);
  });

  testWidgets('a grant recorded in another language stays visible',
      (tester) async {
    final auth = await _signedIn([_policy('ru', granted: true), _policy('en')]);
    addTearDown(auth.dispose);
    await _show(tester, auth, 'en');
    final tile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(tile.value, isTrue);
    expect(find.textContaining('The document is in: Русский'), findsOneWidget);
  });
}
