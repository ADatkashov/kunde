import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_mobile/core/localization/kunde_localizations.dart';
import 'package:kunde_mobile/features/identity/auth_repository.dart';
import 'package:kunde_mobile/features/partner/partner_hub.dart';
import 'package:kunde_mobile/features/partner/partner_ops_api.dart';

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

const _partnerId = '11111111-2222-3333-4444-555555555555';
const _orderId = '66666666-7777-8888-9999-000000000000';
const _bookingId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> _order(String status, List<String> next) => {
      'customerRef': 'abcd1234',
      'allowedNext': next,
      'respondBy': null,
      'reminderAt': null,
      'order': {
        'id': _orderId,
        'restaurantName': 'Кухня партнёра',
        'status': status,
        'paymentMethod': 'CASH_ON_DELIVERY',
        'totalMinor': 79000,
        'addressLabel': 'Дом',
        'addressText': 'Алматы, пр. Абая 10',
        'comment': null,
        'cancelReason': null,
        'items': [
          {'name': 'Плов', 'quantity': 2, 'optionsText': ''}
        ],
        'timeline': [
          {
            'status': 'PLACED',
            'at': '2026-11-16T12:00:00+05:00',
            'actor': 'CUSTOMER',
            'reason': null
          }
        ],
      },
    };

Map<String, dynamic> _booking(String status, List<String> actions) => {
      'id': _bookingId,
      'customerRef': 'abcd1234',
      'serviceName': 'Мужская стрижка',
      'masterName': 'Тимур',
      'status': status,
      'startsAt': '2026-11-17T10:00:00+05:00',
      'endsAt': '2026-11-17T10:45:00+05:00',
      'durationMinutes': 45,
      'priceMinor': 60000,
      'comment': null,
      'addressText': null,
      'areaSqm': null,
      'cancelReason': null,
      'allowedActions': actions,
      'timeline': [
        {
          'status': 'PENDING',
          'at': '2026-11-16T12:00:00+05:00',
          'actor': 'CUSTOMER',
          'reason': null
        }
      ],
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

Future<void> _show(WidgetTester tester, AuthRepository auth,
    {String role = 'OWNER', String language = 'ru'}) async {
  await tester.pumpWidget(MaterialApp(
    locale: Locale(language),
    supportedLocales: KundeLocalizations.supportedLocales,
    localizationsDelegates: KundeLocalizations.localizationsDelegates,
    home: PartnerHubPage(auth: auth, partner: {
      'id': _partnerId,
      'displayName': 'Демо-партнёр',
      'verificationStatus': 'APPROVED',
      'role': role,
    }),
  ));
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  test('api builds partner-scoped paths and validates ids', () async {
    final seen = <http.Request>[];
    final auth = _auth((request) async {
      seen.add(request);
      return _json(request.method == 'GET' ? [] : <String, dynamic>{});
    });
    await auth.login();
    final api = PartnerOpsApi(auth, _partnerId);
    await api.foodOrders('history');
    expect(
        seen.last.url.path, '/api/v1/partner/partners/$_partnerId/food/orders');
    expect(seen.last.url.queryParameters['scope'], 'history');
    await api.setFoodOrderStatus(_orderId, 'CANCELLED',
        reason: 'нет продуктов');
    expect(jsonDecode(seen.last.body),
        {'status': 'CANCELLED', 'reason': 'нет продуктов'});
    await api.bookingAction(_bookingId, 'CONFIRM');
    expect(jsonDecode(seen.last.body), {'action': 'CONFIRM'});
    await api.updateDish(_partnerId, _orderId, clearStock: true);
    expect(jsonDecode(seen.last.body), {'clearStock': true});
    expect(() => PartnerOpsApi(auth, 'not-an-id'), throwsArgumentError);
    expect(() => api.bookingAction('../x', 'CONFIRM'), throwsArgumentError);
  });

  testWidgets('partner sees a new order and accepts it; the list refreshes',
      (tester) async {
    var status = 'PLACED';
    final posted = <Map<String, dynamic>>[];
    final auth = _auth((request) async {
      final path = request.url.path;
      if (request.method == 'POST' && path.endsWith('/status')) {
        posted.add(jsonDecode(request.body) as Map<String, dynamic>);
        status = 'ACCEPTED';
        return _json(_order(status, ['PREPARING', 'CANCELLED']));
      }
      if (path.endsWith('/food/orders')) {
        return _json([
          _order(
              status,
              status == 'PLACED'
                  ? ['ACCEPTED', 'CANCELLED']
                  : ['PREPARING', 'CANCELLED'])
        ]);
      }
      return _json([]);
    });
    await auth.login();
    await _show(tester, auth);
    expect(find.textContaining('Кухня партнёра'), findsOneWidget);
    expect(find.text('Новый'), findsOneWidget);
    expect(find.text('2 × Плов'), findsOneWidget);
    await tester.tap(find.text('Принять'));
    await tester.pumpAndSettle();
    expect(posted, [
      {'status': 'ACCEPTED'}
    ]);
    expect(find.text('Принят'), findsOneWidget);
    expect(find.text('Готовить'), findsOneWidget);
  });

  testWidgets('rejecting an order asks for a reason and sends it',
      (tester) async {
    final posted = <Map<String, dynamic>>[];
    final auth = _auth((request) async {
      if (request.method == 'POST') {
        posted.add(jsonDecode(request.body) as Map<String, dynamic>);
        return _json(_order('CANCELLED', []));
      }
      if (request.url.path.endsWith('/food/orders')) {
        return _json([
          _order('PLACED', ['ACCEPTED', 'CANCELLED'])
        ]);
      }
      return _json([]);
    });
    await auth.login();
    await _show(tester, auth);
    await tester.tap(find.text('Отклонить'));
    await tester.pumpAndSettle();
    final confirm = find.widgetWithText(FilledButton, 'Подтвердить');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'нет продуктов');
    await tester.pump();
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(posted, [
      {'status': 'CANCELLED', 'reason': 'нет продуктов'}
    ]);
  });

  testWidgets(
      'a stale action shows the refresh message instead of failing silently',
      (tester) async {
    final auth = _auth((request) async {
      if (request.method == 'POST') {
        return _json({'code': 'ORDER_TRANSITION_INVALID'}, 409);
      }
      if (request.url.path.endsWith('/food/orders')) {
        return _json([
          _order('PLACED', ['ACCEPTED', 'CANCELLED'])
        ]);
      }
      return _json([]);
    });
    await auth.login();
    await _show(tester, auth);
    await tester.tap(find.text('Принять'));
    await tester.pumpAndSettle();
    expect(find.text('Статус уже изменился. Список обновлён.'), findsOneWidget);
  });

  testWidgets('bookings tab lists requests and confirms one', (tester) async {
    final posted = <Map<String, dynamic>>[];
    final auth = _auth((request) async {
      final path = request.url.path;
      if (request.method == 'POST' && path.endsWith('/action')) {
        posted.add(jsonDecode(request.body) as Map<String, dynamic>);
        return _json(_booking('CONFIRMED', ['CANCEL']));
      }
      if (path.endsWith('/booking/bookings')) {
        return _json([
          _booking('PENDING', ['CONFIRM', 'REJECT'])
        ]);
      }
      return _json([]);
    });
    await auth.login();
    await _show(tester, auth);
    await tester.tap(find.text('Записи'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Мужская стрижка'), findsOneWidget);
    expect(find.text('Ждёт ответа'), findsOneWidget);
    await tester.tap(find.text('Подтвердить'));
    await tester.pumpAndSettle();
    expect(posted, [
      {'action': 'CONFIRM'}
    ]);
  });

  testWidgets('availability tab toggles a service; operators cannot edit hours',
      (tester) async {
    final patched = <Map<String, dynamic>>[];
    final auth = _auth((request) async {
      final path = request.url.path;
      if (request.method == 'PATCH') {
        patched.add(jsonDecode(request.body) as Map<String, dynamic>);
        return _json(<String, dynamic>{});
      }
      if (path.endsWith('/food/restaurants')) return _json([]);
      if (path.endsWith('/booking/venues')) {
        return _json([
          {
            'id': _bookingId,
            'name': 'Барбершоп партнёра',
            'category': 'BARBER',
            'open': true
          }
        ]);
      }
      if (path.endsWith('/services')) {
        return _json([
          {
            'id': _orderId,
            'name': 'Мужская стрижка',
            'durationMinutes': 45,
            'priceMinor': 60000,
            'available': true
          }
        ]);
      }
      if (path.endsWith('/masters')) {
        return _json([
          {
            'id': _partnerId,
            'name': 'Тимур',
            'active': true,
            'hours': [
              {'day': 1, 'from': '09:00', 'to': '20:00'}
            ]
          }
        ]);
      }
      return _json([]);
    });
    await auth.login();
    await _show(tester, auth, role: 'OPERATOR');
    await tester.tap(find.text('Доступность'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Барбершоп партнёра'));
    await tester.pumpAndSettle();
    // Operators may toggle availability but not the venue switch or the schedule.
    final venueSwitch = find.widgetWithText(SwitchListTile, 'Принимает записи');
    expect(tester.widget<SwitchListTile>(venueSwitch).onChanged, isNull);
    expect(find.textContaining('1 дн.'), findsOneWidget);
    await tester.tap(find.text('Тимур'));
    await tester.pumpAndSettle();
    expect(find.text('Расписание'), findsNothing);
    await tester.tap(find.widgetWithText(SwitchListTile, 'Мужская стрижка'));
    await tester.pumpAndSettle();
    expect(patched, [
      {'available': false}
    ]);
  });

  testWidgets('a newly arrived order raises an alert; the first load is silent',
      (tester) async {
    var arrived = false;
    final auth = _auth((request) async {
      if (request.url.path.endsWith('/food/orders')) {
        final order = _order('PLACED', ['ACCEPTED', 'CANCELLED']);
        order['respondBy'] =
            DateTime.now().add(const Duration(minutes: 5)).toIso8601String();
        order['reminderAt'] =
            DateTime.now().add(const Duration(minutes: 2)).toIso8601String();
        return _json(arrived ? [order] : []);
      }
      return _json([]);
    });
    await auth.login();
    await _show(tester, auth, language: 'en');
    expect(find.text('New order!'), findsNothing);
    arrived = true;
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(find.text('New order!'), findsOneWidget);
    expect(find.textContaining('Reply by'), findsOneWidget);
  });
}
