import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_mobile/core/localization/kunde_formats.dart';
import 'package:kunde_mobile/core/localization/kunde_localizations.dart';
import 'package:kunde_mobile/features/identity/auth_repository.dart';
import 'package:kunde_mobile/features/partner/partner_panel.dart';

class _Vault implements TokenVault {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async {}
  @override
  Future<void> clear() async {}
}

class _Gateway implements OAuthGateway {
  int refreshes = 0;
  @override
  Future<AuthTokens> login({bool register = false}) async => AuthTokens(
      'access',
      'refresh',
      null,
      DateTime.now().add(const Duration(minutes: 5)));
  @override
  Future<AuthTokens> refresh(String refreshToken) {
    refreshes++;
    return login();
  }

  @override
  Future<void> logout(String? idToken) async {}
}

const _partnerId = '11111111-2222-3333-4444-555555555555';
const _offeringId = '66666666-7777-8888-9999-000000000000';
const _categoryId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';

Map<String, dynamic> _partner(
        {String status = 'PENDING_REVIEW', String role = 'OWNER'}) =>
    {
      'id': _partnerId,
      'displayName': 'Synthetic Cafe',
      'verificationStatus': status,
      'version': 0,
      'role': role,
    };

Map<String, dynamic> _offering(
        {String status = 'DRAFT', int? price = 250050, int version = 0}) =>
    {
      'id': _offeringId,
      'partnerId': _partnerId,
      'categoryId': _categoryId,
      'kind': 'PRODUCT',
      'nameRu': 'Плов',
      'nameKk': 'Палау',
      'nameEn': 'Pilaf',
      'status': status,
      'priceMinor': price,
      'currency': 'KZT',
      'availability': 'AVAILABLE',
      'version': version,
    };

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json; charset=utf-8'});

(AuthRepository, _Gateway) _auth(
    Future<http.Response> Function(http.Request) handler) {
  final gateway = _Gateway();
  final auth = AuthRepository(
    gateway: gateway,
    vault: _Vault(),
    apiBase: Uri.parse('https://api.example.test/api/v1/'),
    client: MockClient(handler),
  );
  addTearDown(auth.dispose);
  return (auth, gateway);
}

Future<void> _pumpUntilLoaded(WidgetTester tester) async {
  await tester.pump();
  await tester.pumpAndSettle();
}

Future<void> _show(WidgetTester tester, Widget child,
    [String language = 'en']) async {
  await tester.pumpWidget(MaterialApp(
    locale: Locale(language),
    supportedLocales: KundeLocalizations.supportedLocales,
    localizationsDelegates: KundeLocalizations.localizationsDelegates,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ));
  await _pumpUntilLoaded(tester);
}

void main() {
  group('parseKztToTiyn', () {
    test('turns a typed KZT amount into tiyn', () {
      expect(parseKztToTiyn(''), isNull);
      expect(parseKztToTiyn('  '), isNull);
      expect(parseKztToTiyn('2500'), 250000);
      expect(parseKztToTiyn('2 500,5'), 250050);
      expect(parseKztToTiyn('2500.50'), 250050);
      expect(parseKztToTiyn('0'), 0);
      expect(parseKztToTiyn('99999999.99'), 9999999999);
    });

    test('rejects anything that is not a plain amount', () {
      for (final bad in ['-1', '1.234', 'abc', '1e3', '100000000', '1..2']) {
        expect(parseKztToTiyn(bad), invalidPrice, reason: bad);
      }
    });
  });

  group('repository', () {
    test('partner calls use the documented paths, bodies and ids', () async {
      final seen = <http.Request>[];
      final (auth, _) = _auth((request) async {
        seen.add(request);
        if (request.url.path.endsWith('/applications')) {
          return _json(_partner(), 201);
        }
        if (request.method == 'POST' &&
            request.url.path.contains('/offerings')) {
          return _json(
              _offering(), request.url.path.endsWith('offerings') ? 201 : 200);
        }
        return _json(
            request.url.path.endsWith('partners') ? [_partner()] : _offering());
      });
      await auth.login();
      await auth.applyAsPartner('  Synthetic Cafe ');
      expect(jsonDecode(seen.last.body), {'displayName': 'Synthetic Cafe'});
      await auth.partners();
      await auth.createPartnerOffering(_partnerId,
          categoryId: _categoryId,
          kind: 'PRODUCT',
          nameRu: ' Плов ',
          nameKk: 'Палау',
          priceMinor: 250050,
          available: true);
      expect(
          seen.last.url.path, '/api/v1/partner/partners/$_partnerId/offerings');
      expect(jsonDecode(seen.last.body), {
        'categoryId': _categoryId,
        'kind': 'PRODUCT',
        'nameRu': 'Плов',
        'nameKk': 'Палау',
        'priceMinor': 250050,
        'availability': 'AVAILABLE',
      });
      await auth.updatePartnerOffering(_partnerId, _offeringId,
          nameRu: 'Плов',
          nameKk: 'Палау',
          priceMinor: null,
          available: false,
          version: 3);
      expect(seen.last.method, 'PATCH');
      expect(jsonDecode(seen.last.body), containsPair('version', 3));
      expect(jsonDecode(seen.last.body), containsPair('priceMinor', null));
      expect(jsonDecode(seen.last.body),
          containsPair('availability', 'UNAVAILABLE'));
      await auth.setPartnerOfferingPublished(_partnerId, _offeringId,
          published: false, version: 4);
      expect(seen.last.url.path.endsWith('/$_offeringId/unpublish'), isTrue);
      expect(seen.last.headers['Authorization'], 'Bearer access');
    });

    test('invalid names and ids never reach the network', () async {
      var calls = 0;
      final (auth, _) = _auth((_) async {
        calls++;
        return _json([]);
      });
      await auth.login();
      expect(() => auth.applyAsPartner('  '), throwsArgumentError);
      expect(() => auth.applyAsPartner('x' * 121), throwsArgumentError);
      expect(() => auth.partnerOfferings('../../me'), throwsArgumentError);
      expect(
          () => auth.setPartnerOfferingPublished(_partnerId, 'nope',
              published: true, version: 0),
          throwsArgumentError);
      expect(calls, 0);
    });

    test('a 403 on the partner list means not a partner yet', () async {
      final (auth, _) = _auth((_) async => http.Response('{}', 403));
      await auth.login();
      expect(await auth.partners(), isEmpty);
    });

    test('other errors on the partner list are surfaced', () async {
      final (auth, _) = _auth((_) async => http.Response('{}', 500));
      await auth.login();
      expect(auth.partners(), throwsA(isA<IdentityApiError>()));
    });
  });

  group('PartnerPanel', () {
    testWidgets('a non-partner sees nothing when applying is disabled',
        (tester) async {
      final (auth, _) = _auth((request) async => http.Response('{}', 403));
      await auth.login();
      await _show(tester, PartnerPanel(auth: auth, allowApply: false));
      expect(find.text('For partners'), findsNothing);
      expect(find.text('Become a partner'), findsNothing);
    });

    testWidgets('partner staff still see the section when applying is disabled',
        (tester) async {
      final (auth, _) =
          _auth((request) async => _json([_partner(status: 'APPROVED')]));
      await auth.login();
      await _show(tester, PartnerPanel(auth: auth, allowApply: false));
      expect(find.text('For partners'), findsOneWidget);
      expect(find.text('Synthetic Cafe'), findsOneWidget);
      expect(find.text('Become a partner'), findsNothing);
    });

    testWidgets('applying refreshes the token and then lists the partner',
        (tester) async {
      late _Gateway gateway;
      var applied = false;
      final (auth, gw) = _auth((request) async {
        if (request.method == 'POST') {
          applied = true;
          return _json(_partner(), 201);
        }
        // Before the refresh the token has no partner scope: the server says 403.
        return applied && gateway.refreshes > 0
            ? _json([_partner()])
            : http.Response('{}', 403);
      });
      gateway = gw;
      await auth.login();
      await _show(tester, PartnerPanel(auth: auth));
      expect(find.text('Become a partner'), findsOneWidget);
      expect(find.textContaining('only after KUNDE reviews'), findsOneWidget);
      await tester.tap(find.text('Become a partner'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, 'Send'))
              .onPressed,
          isNull);
      await tester.enterText(find.byType(TextField), 'Synthetic Cafe');
      await tester.pump();
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(gateway.refreshes, 1);
      expect(find.text('Synthetic Cafe'), findsOneWidget);
      expect(find.text('Under review · Owner'), findsOneWidget);
      expect(find.text('Become a partner'), findsNothing);
    });

    testWidgets('too many applications gives an honest message',
        (tester) async {
      final (auth, _) = _auth((request) async => request.method == 'POST'
          ? http.Response('{}', 409)
          : http.Response('{}', 403));
      await auth.login();
      await _show(tester, PartnerPanel(auth: auth));
      await tester.tap(find.text('Become a partner'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Another Cafe');
      await tester.pump();
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(find.text('Too many applications'), findsOneWidget);
    });

    testWidgets('loading failure can be retried', (tester) async {
      var fail = true;
      final (auth, _) = _auth((_) async => fail
          ? http.Response('', 503)
          : _json([_partner(status: 'APPROVED')]));
      await auth.login();
      await _show(tester, PartnerPanel(auth: auth));
      expect(find.textContaining('Loading failed'), findsOneWidget);
      fail = false;
      await tester.tap(find.textContaining('Loading failed'));
      await tester.pumpAndSettle();
      expect(find.text('Approved · Owner'), findsOneWidget);
    });

    testWidgets('Russian and Kazakh labels render', (tester) async {
      final (auth, _) = _auth((_) async => _json([_partner()]));
      await auth.login();
      await _show(tester, PartnerPanel(auth: auth), 'ru');
      expect(find.text('Партнёрам'), findsOneWidget);
      expect(find.text('На проверке · Владелец'), findsOneWidget);
      await _show(tester, PartnerPanel(auth: auth), 'kk');
      expect(find.text('Серіктестерге'), findsOneWidget);
      expect(find.text('Тексеруде · Иесі'), findsOneWidget);
    });
  });

  group('PartnerOfferingsPage', () {
    Future<void> open(WidgetTester tester, AuthRepository auth,
        Map<String, dynamic> partner) async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        supportedLocales: KundeLocalizations.supportedLocales,
        localizationsDelegates: KundeLocalizations.localizationsDelegates,
        home: PartnerOfferingsPage(auth: auth, partner: partner),
      ));
      await _pumpUntilLoaded(tester);
    }

    testWidgets('shows the KZT price and blocks publishing until approved',
        (tester) async {
      final (auth, _) = _auth((_) async => _json([_offering()]));
      await auth.login();
      await open(tester, auth, _partner());
      expect(find.text('Плов'), findsNothing);
      expect(find.text('Pilaf'), findsOneWidget);
      final price = KundeFormats.money(250050, 'KZT', const Locale('en'));
      expect(find.text('$price · Available · Draft'), findsOneWidget);
      expect(find.textContaining('Publishing becomes available after KUNDE'),
          findsOneWidget);
      expect(
          tester
              .widget<TextButton>(find.widgetWithText(TextButton, 'Publish'))
              .onPressed,
          isNull);
    });

    testWidgets('an approved partner publishes and withdraws with the version',
        (tester) async {
      final posts = <http.Request>[];
      var status = 'DRAFT';
      final (auth, _) = _auth((request) async {
        if (request.method == 'POST') {
          posts.add(request);
          status =
              request.url.path.endsWith('/publish') ? 'PUBLISHED' : 'DRAFT';
          return _json(_offering(status: status, version: 1));
        }
        return _json([_offering(status: status)]);
      });
      await auth.login();
      await open(tester, auth, _partner(status: 'APPROVED'));
      await tester.tap(find.text('Publish'));
      await tester.pumpAndSettle();
      expect(posts.single.url.path.endsWith('/$_offeringId/publish'), isTrue);
      expect(jsonDecode(posts.single.body), {'version': 0});
      expect(find.textContaining('Published'), findsOneWidget);
      await tester.tap(find.text('Withdraw'));
      await tester.pumpAndSettle();
      expect(posts.last.url.path.endsWith('/unpublish'), isTrue);
      expect(find.textContaining('Draft'), findsOneWidget);
    });

    testWidgets('a server refusal is explained and the list is reloaded',
        (tester) async {
      final (auth, _) = _auth((request) async => request.method == 'POST'
          ? http.Response('{}', 409)
          : _json([_offering(price: null)]));
      await auth.login();
      await open(tester, auth, _partner(status: 'APPROVED'));
      expect(find.textContaining('No price set'), findsOneWidget);
      await tester.tap(find.text('Publish'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Not possible'), findsOneWidget);
    });

    testWidgets('operators can read but not change or add anything',
        (tester) async {
      final (auth, _) = _auth((_) async => _json([_offering()]));
      await auth.login();
      await open(tester, auth, _partner(status: 'APPROVED', role: 'OPERATOR'));
      expect(find.text('Pilaf'), findsOneWidget);
      expect(find.text('Publish'), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('a new offering is created from the form with a tiyn price',
        (tester) async {
      http.Request? created;
      final (auth, _) = _auth((request) async {
        if (request.url.path.endsWith('/partner/categories')) {
          return _json([
            {
              'id': _categoryId,
              'code': 'food-ordering',
              'nameRu': 'Еда',
              'nameKk': 'Тағам',
              'nameEn': 'Food',
              'status': 'DRAFT'
            }
          ]);
        }
        if (request.method == 'POST') {
          created = request;
          return _json(_offering(), 201);
        }
        return _json(created == null ? [] : [_offering()]);
      });
      await auth.login();
      await open(tester, auth, _partner(status: 'APPROVED'));
      expect(find.text('No offerings yet'), findsOneWidget);
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
              .onPressed,
          isNull);
      await tester.enterText(
          find.widgetWithText(TextField, 'Name (RU)'), 'Плов');
      await tester.enterText(
          find.widgetWithText(TextField, 'Name (KK)'), 'Палау');
      await tester.enterText(
          find.widgetWithText(TextField, 'Final price, ₸'), '2500,5x');
      await tester.pump();
      expect(find.text('For example 2500 or 2500.50'), findsOneWidget);
      await tester.enterText(
          find.widgetWithText(TextField, 'Final price, ₸'), '2500,5');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final body = jsonDecode(created!.body) as Map<String, dynamic>;
      expect(body['priceMinor'], 250050);
      expect(body['categoryId'], _categoryId);
      expect(body['kind'], 'PRODUCT');
      expect(body['availability'], 'UNAVAILABLE');
      expect(find.text('Pilaf'), findsOneWidget);
    });

    testWidgets('editing sends the current version and keeps the price',
        (tester) async {
      http.Request? patched;
      final (auth, _) = _auth((request) async {
        if (request.method == 'PATCH') {
          patched = request;
          return _json(_offering(version: 1));
        }
        return _json([_offering(version: 7)]);
      });
      await auth.login();
      await open(tester, auth, _partner(status: 'APPROVED'));
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      // The form starts from the current price, typed back as KZT.
      expect(find.text('2500.50'), findsOneWidget);
      await tester.enterText(
          find.widgetWithText(TextField, 'Name (RU)'), 'Плов с мясом');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final body = jsonDecode(patched!.body) as Map<String, dynamic>;
      expect(body['version'], 7);
      expect(body['nameRu'], 'Плов с мясом');
      expect(body['priceMinor'], 250050);
    });
  });
}
