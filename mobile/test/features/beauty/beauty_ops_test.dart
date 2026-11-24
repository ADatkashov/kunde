import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_localization/kunde_localizations.dart';
import 'package:kunde_ui/beauty_theme.dart';
import 'package:kunde_mobile/features/beauty/presentation/beauty_partner_screen.dart';
import 'package:kunde_auth/auth_repository.dart';

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

class _Server {
  bool linked = false;
  bool online = true;
  String status = 'CONFIRMED';
  final calls = <String>[];

  http.Response _json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status,
          headers: {'content-type': 'application/json; charset=utf-8'});

  Future<http.Response> handle(http.Request r) async {
    final path = r.url.path.replaceFirst('/api/v1/', '');
    calls.add('${r.method} $path');
    if (path.endsWith('/beauty/overview')) {
      return _json({
        'salons': [
          {'id': 's1', 'name': 'LUNA Beauty Studio', 'addressText': 'Алматы'}
        ],
        'bookingsToday': 24,
        'bookingsDeltaPercent': 20,
        'revenueTodayMinor': 62400000,
        'revenueDeltaPercent': 28,
        'pendingRequests': 3,
        'mastersOnline': 2,
        'mastersTotal': 3,
      });
    }
    if (path.endsWith('/beauty/masters')) {
      return _json([
        {
          'id': 'm1',
          'venueId': 's1',
          'name': 'Алия С.',
          'specialty': 'Колорист',
          'online': true,
          'linked': false,
          'inviteCode': 'DEMO-ALIYA'
        }
      ]);
    }
    if (path == 'executor/beauty/link') {
      if ((jsonDecode(r.body) as Map)['code'] != 'DEMO-ALIYA') {
        return _json({'code': 'INVITE_INVALID'}, 404);
      }
      linked = true;
      return http.Response('', 204);
    }
    if (path == 'executor/beauty/today') {
      if (!linked) return _json({'code': 'NOT_A_MASTER'}, 404);
      return _json({
        'masterName': 'Алия С.',
        'venueName': 'LUNA Beauty Studio',
        'online': online,
        'todayCount': 3,
        'appointments': [
          {
            'id': 'a1',
            'bookingNumber': 'KND-772431',
            'serviceName': 'Окрашивание волос',
            'venueName': 'LUNA Beauty Studio',
            'venueAddress': 'Алматы',
            'clientName': 'Айгерим Т.',
            'startsAt': '2026-11-20T14:00:00+05:00',
            'endsAt': '2026-11-20T17:00:00+05:00',
            'status': status,
            'canStart': status == 'CONFIRMED',
            'canComplete': status == 'IN_PROGRESS',
            'canMarkNoShow': false,
          },
          {
            'id': 'a2',
            'bookingNumber': 'KND-772432',
            'serviceName': 'Маникюр',
            'venueName': 'LUNA Beauty Studio',
            'venueAddress': 'Алматы',
            'clientName': 'Данияр С.',
            'startsAt': '2026-11-20T17:30:00+05:00',
            'endsAt': '2026-11-20T18:30:00+05:00',
            'status': 'CONFIRMED',
            'canStart': false,
            'canComplete': false,
            'canMarkNoShow': false,
          }
        ],
      });
    }
    if (path == 'executor/beauty/availability') {
      online = (jsonDecode(r.body) as Map)['online'] as bool;
      return http.Response('', 204);
    }
    if (path == 'executor/beauty/appointments/a1/start') {
      status = 'IN_PROGRESS';
      return http.Response('', 204);
    }
    if (path == 'executor/beauty/earnings') {
      return _json({
        'todayMinor': 1750000,
        'weekMinor': 3500000,
        'monthMinor': 9000000,
        'completedToday': 1,
        'completedMonth': 4,
        'currency': 'KZT'
      });
    }
    if (path == 'beauty/categories') {
      return _json([
        {
          'code': 'HAIR',
          'nameRu': 'Волосы',
          'nameKk': 'Шаш',
          'nameEn': 'Hair',
          'icon': 'brush',
          'featured': true
        }
      ]);
    }
    if (path == 'admin/beauty/analytics') {
      return _json({
        'days': 7,
        'salons': 6,
        'salonsDeltaPercent': null,
        'bookings': 48,
        'bookingsDeltaPercent': 22,
        'revenueMinor': 61240000,
        'revenueDeltaPercent': 27,
        'averageCheckMinor': 1267000,
        'averageCheckDeltaPercent': 8,
        'bookingsByDay': [
          for (var i = 0; i < 7; i++)
            {'date': '2026-11-${14 + i}', 'bookings': i + 1}
        ],
        'categories': [
          {'code': 'HAIR', 'bookings': 30, 'percent': 62}
        ],
        'recent': [
          {
            'bookingNumber': 'KND-772431',
            'client': 'Айгерим Т.',
            'salon': 'LUNA Beauty',
            'service': 'Окрашивание',
            'amountMinor': 2500000,
            'status': 'COMPLETED'
          }
        ],
      });
    }
    return http.Response('not found', 404);
  }
}

Future<AuthRepository> _auth(_Server server) async {
  final auth = AuthRepository(
    gateway: _Gateway(),
    vault: _Vault(),
    apiBase: Uri.parse('https://api.example.test/api/v1/'),
    client: MockClient(server.handle),
  );
  await auth.signIn(AuthTokens('access', 'refresh', null,
      DateTime.now().add(const Duration(minutes: 5))));
  addTearDown(auth.dispose);
  return auth;
}

Future<void> _show(WidgetTester tester, Widget screen,
    {String language = 'ru'}) async {
  tester.view.physicalSize = const Size(1080, 2600);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: KundeLocalizations.localizationsDelegates,
    supportedLocales: KundeLocalizations.supportedLocales,
    locale: Locale(language),
    home: BeautyScope(child: screen),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('partner overview shows real numbers, pending badge and the menu',
      (tester) async {
    final auth = await _auth(_Server());
    await _show(
        tester,
        BeautyPartnerScreen(
            auth: auth, partnerId: 'p1', onOpenBookings: () {}));

    expect(find.text('KUNDE Partner'), findsOneWidget);
    expect(find.text('LUNA Beauty Studio'), findsOneWidget);
    expect(find.text('Записей сегодня'), findsOneWidget);
    expect(find.text('24'), findsOneWidget);
    expect(find.text('+20%'), findsOneWidget);
    expect(find.text('624 000 ₸'), findsOneWidget);
    expect(find.text('+28%'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    for (final label in [
      'Расписание мастеров',
      'Записи и клиенты',
      'Сотрудники',
    ]) {
      expect(find.text(label), findsOneWidget);
    }

    await tester.tap(find.text('Сотрудники'));
    await tester.pumpAndSettle();
    expect(find.text('DEMO-ALIYA'), findsOneWidget);
  });
}
