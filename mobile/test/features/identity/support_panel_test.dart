import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_mobile/core/localization/kunde_localizations.dart';
import 'package:kunde_mobile/features/identity/auth_repository.dart';
import 'package:kunde_mobile/features/identity/support_panel.dart';

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
      DateTime.now().add(const Duration(minutes: 5)));
  @override
  Future<AuthTokens> refresh(String refreshToken) => login();
  @override
  Future<void> logout(String? idToken) async {}
}

const _id = '11111111-2222-3333-4444-555555555555';

Map<String, dynamic> _case({String status = 'OPEN'}) => {
      'id': _id,
      'category': 'GENERAL',
      'message': 'Synthetic question',
      'status': status,
    };

AuthRepository _auth(Future<http.Response> Function(http.Request) handler) {
  final auth = AuthRepository(
    gateway: _Gateway(),
    vault: _Vault(),
    apiBase: Uri.parse('https://api.example.test/api/v1/'),
    client: MockClient(handler),
  );
  addTearDown(auth.dispose);
  return auth;
}

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json; charset=utf-8'});

Future<void> _show(WidgetTester tester, AuthRepository auth,
    [String language = 'en']) async {
  await auth.login();
  await tester.pumpWidget(MaterialApp(
    locale: Locale(language),
    supportedLocales: KundeLocalizations.supportedLocales,
    localizationsDelegates: KundeLocalizations.localizationsDelegates,
    home:
        Scaffold(body: SingleChildScrollView(child: SupportPanel(auth: auth))),
  ));
  for (var i = 0;
      i < 40 && find.byType(LinearProgressIndicator).evaluate().isNotEmpty ||
          i == 0;
      i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('repository', () {
    test('open case sends a stable Idempotency-Key and trimmed body', () async {
      late http.Request seen;
      final auth = _auth((request) async {
        seen = request;
        return _json(_case(), 201);
      });
      await auth.login();
      await auth.openSupportCase(
          category: 'GENERAL',
          message: '  hi  ',
          idempotencyKey: 'abcdefabcdefabcdefabcdefabcdefab');
      expect(seen.method, 'POST');
      expect(seen.url.path, '/api/v1/me/support/cases');
      expect(
          seen.headers['Idempotency-Key'], 'abcdefabcdefabcdefabcdefabcdefab');
      expect(jsonDecode(seen.body), {'category': 'GENERAL', 'message': 'hi'});
    });

    test('invalid input never reaches the network', () async {
      var calls = 0;
      final auth = _auth((request) async {
        calls++;
        return _json(_case(), 201);
      });
      await auth.login();
      const key = 'abcdefabcdefabcdefabcdefabcdefab';
      for (final bad in [
        () => auth.openSupportCase(
            category: 'ORDER', message: 'x', idempotencyKey: key),
        () => auth.openSupportCase(
            category: 'GENERAL', message: '   ', idempotencyKey: key),
        () => auth.openSupportCase(
            category: 'GENERAL', message: 'x' * 2001, idempotencyKey: key),
        () => auth.openSupportCase(
            category: 'GENERAL', message: 'x', idempotencyKey: 'short'),
        () => auth.requestSupportEscalation('../me'),
      ]) {
        await expectLater(bad(), throwsArgumentError);
      }
      expect(calls, 0);
    });
  });

  group('panel', () {
    testWidgets('empty state promises nothing', (tester) async {
      await _show(tester, _auth((_) async => _json([])));
      expect(find.text('No support requests yet'), findsOneWidget);
      expect(find.text('Contact support'), findsOneWidget);
    });

    testWidgets('error state offers retry', (tester) async {
      var fail = true;
      final auth =
          _auth((_) async => fail ? http.Response('', 503) : _json([]));
      await _show(tester, auth);
      expect(find.textContaining('Loading failed'), findsOneWidget);
      fail = false;
      await tester.tap(find.textContaining('Loading failed'));
      await tester.pumpAndSettle();
      expect(find.text('No support requests yet'), findsOneWidget);
    });

    testWidgets('open case can be escalated once, with an honest notice',
        (tester) async {
      var status = 'OPEN';
      final methods = <String>[];
      final auth = _auth((request) async {
        methods.add('${request.method} ${request.url.path}');
        if (request.method == 'POST') {
          status = 'ESCALATION_REQUESTED';
          return _json(_case(status: status));
        }
        return _json([_case(status: status)]);
      });
      await _show(tester, auth);
      expect(find.textContaining('Open'), findsOneWidget);
      await tester.tap(find.text('Escalate'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No response time is guaranteed'),
          findsOneWidget);
      await tester.tap(find.text('Request'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Escalation requested'), findsOneWidget);
      expect(find.text('Escalate'), findsNothing);
      expect(methods.where((m) => m.startsWith('POST')).length, 1);
    });

    testWidgets('new request is sent from the dialog and the list reloads',
        (tester) async {
      http.Request? posted;
      var created = false;
      final auth = _auth((request) async {
        if (request.method == 'POST') {
          posted = request;
          created = true;
          return _json(_case(), 201);
        }
        return _json(created ? [_case()] : []);
      });
      await _show(tester, auth);
      await tester.tap(find.text('Contact support'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, 'Send'))
              .onPressed,
          isNull);
      await tester.enterText(find.byType(TextField), 'Synthetic question');
      await tester.pump();
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(posted!.headers['Idempotency-Key'],
          matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(find.textContaining('Synthetic question'), findsOneWidget);
    });

    testWidgets('Russian and Kazakh labels render', (tester) async {
      await _show(tester, _auth((_) async => _json([])), 'ru');
      expect(find.text('Обращений пока нет'), findsOneWidget);
      await _show(tester, _auth((_) async => _json([])), 'kk');
      expect(find.text('Әзірге өтініштер жоқ'), findsOneWidget);
    });
  });
}
