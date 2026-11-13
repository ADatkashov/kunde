import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_mobile/core/localization/kunde_localizations.dart';
import 'package:kunde_mobile/features/identity/address_panel.dart';
import 'package:kunde_mobile/features/identity/auth_repository.dart';

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

const _id = '11111111-2222-3333-4444-555555555555';

Map<String, dynamic> _address(String label, {required bool serviceable}) => {
      'id': _id,
      'label': label,
      'formattedAddress': 'Synthetic street 1',
      'version': 0,
      'serviceable': serviceable,
    };

Future<AuthRepository> _signedIn(List<Map<String, dynamic>> items) async {
  final auth = AuthRepository(
    gateway: _Gateway(),
    vault: _Vault(),
    apiBase: Uri.parse('https://api.example.test/api/v1/'),
    client:
        MockClient((request) async => http.Response(jsonEncode(items), 200)),
  );
  await auth.login();
  return auth;
}

Widget _app(AuthRepository auth, String language) => MaterialApp(
      locale: Locale(language),
      supportedLocales: KundeLocalizations.supportedLocales,
      localizationsDelegates: KundeLocalizations.localizationsDelegates,
      home: Scaffold(
          body: SingleChildScrollView(child: AddressPanel(auth: auth))),
    );

void main() {
  testWidgets('unconfirmed zone is shown as unavailable, never as confirmed',
      (tester) async {
    final auth = await _signedIn([_address('Home', serviceable: false)]);
    addTearDown(auth.dispose);
    await tester.pumpWidget(_app(auth, 'en'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Serviceability not confirmed'), findsOneWidget);
    expect(find.textContaining('not available yet'), findsOneWidget);
    expect(find.text('Serviceable zone confirmed'), findsNothing);
    expect(find.byIcon(Icons.info_outline), findsOneWidget);
  });

  testWidgets('confirmed zone shows the confirmation in Russian',
      (tester) async {
    final auth = await _signedIn([_address('Дом', serviceable: true)]);
    addTearDown(auth.dispose);
    await tester.pumpWidget(_app(auth, 'ru'));
    await tester.pumpAndSettle();
    expect(find.text('Зона обслуживания подтверждена'), findsOneWidget);
    expect(find.textContaining('недоступны'), findsNothing);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
  });

  testWidgets('status is announced as one semantic label in Kazakh',
      (tester) async {
    final auth = await _signedIn([_address('Үй', serviceable: false)]);
    addTearDown(auth.dispose);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(auth, 'kk'));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(RegExp('Қызмет көрсету аймағы расталмаған')),
      findsOneWidget,
    );
    handle.dispose();
  });
}
