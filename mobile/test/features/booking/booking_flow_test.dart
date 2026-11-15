import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_mobile/features/booking/booking_services.dart';
import 'package:kunde_mobile/features/booking/data/booking_api.dart';
import 'package:kunde_mobile/features/booking/data/booking_models.dart';
import 'package:kunde_mobile/features/booking/presentation/bookings_list.dart';
import 'package:kunde_mobile/features/booking/presentation/services_home_screen.dart';
import 'package:kunde_mobile/features/home/data/platform_snapshot.dart';
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
      DateTime.now().add(const Duration(minutes: 5)));
  @override
  Future<AuthTokens> refresh(String refreshToken) => login();
  @override
  Future<void> logout(String? idToken) async {}
}

const _venueId = '11111111-1111-1111-1111-111111111111';
const _serviceId = '22222222-2222-2222-2222-222222222222';
const _masterId = '33333333-3333-3333-3333-333333333333';

final _venue = {
  'id': _venueId,
  'slug': 'barber-test',
  'category': 'BARBER',
  'name': 'Тест Барбершоп',
  'description': 'Вымышленное заведение',
  'addressText': 'Алматы, Абая 1',
  'emoji': '💈',
  'tone': 'blue',
  'open': true,
  'synthetic': true,
  'fromPriceMinor': 650000,
};

/// In-memory stand-in for the booking backend: slots per date, one master, persisted bookings across app restarts.
class _FakeBackend {
  final bookings = <Map<String, dynamic>>[];
  final keys = <String, String>{};
  bool offline = false;
  bool slotTakenOnBook = false;
  int slotRequests = 0;

  http.Response _json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status,
          headers: {'content-type': 'application/json; charset=utf-8'});

  Future<http.Response> handle(http.Request request) async {
    if (offline) throw http.ClientException('offline');
    final path = request.url.path.replaceFirst('/api/v1/', '');
    final body = request.body.isEmpty
        ? null
        : jsonDecode(request.body) as Map<String, dynamic>;
    if (path == 'booking/venues') return _json([_venue]);
    if (path == 'booking/venues/$_venueId') {
      return _json({
        'venue': _venue,
        'services': [
          {
            'id': _serviceId,
            'name': 'Мужская стрижка',
            'description': 'Ножницы и машинка',
            'durationMinutes': 45,
            'priceMinor': 650000,
            'available': true
          }
        ],
        'masters': [
          {
            'id': _masterId,
            'name': 'Арман',
            'bio': 'Классика',
            'emoji': '💇',
            'tone': 'amber',
            'serviceIds': [_serviceId]
          }
        ],
      });
    }
    if (path == 'booking/slots') {
      slotRequests++;
      final date = request.url.queryParameters['date']!;
      return _json([
        for (final t in ['10:00', '10:15', '11:00'])
          {
            'startsAt': '${date}T$t:00+05:00',
            'masterId': _masterId,
            'masterName': 'Арман'
          }
      ]);
    }
    if (path == 'booking/bookings' && request.method == 'POST') {
      if (slotTakenOnBook) return _json({'code': 'SLOT_TAKEN'}, 409);
      final key = request.headers['Idempotency-Key']!;
      if (keys.containsKey(key)) {
        return _json(bookings.firstWhere((b) => b['id'] == keys[key]));
      }
      final starts = body!['startsAt'] as String;
      final startTime = starts.substring(11, 16);
      final record = {
        'id': 'bbbbbbbb-0000-0000-0000-00000000000${bookings.length + 1}',
        'venueId': _venueId,
        'venueName': 'Тест Барбершоп',
        'venueAddress': 'Алматы, Абая 1',
        'serviceName': 'Мужская стрижка',
        'durationMinutes': 45,
        'masterId': _masterId,
        'masterName': 'Арман',
        'startsAt': starts,
        'endsAt':
            '${starts.substring(0, 11)}${startTime == '10:00' ? '10:45' : '11:45'}:00+05:00',
        'priceMinor': 650000,
        'currency': 'KZT',
        'status': 'CONFIRMED',
        'confirmation': 'DEV_MOCK',
        'comment': body['comment'],
        'cancellable': true,
      };
      bookings.insert(0, record);
      keys[key] = record['id'] as String;
      return _json(record, 201);
    }
    if (path == 'booking/bookings') return _json(bookings);
    if (path.startsWith('booking/bookings/') && path.endsWith('/cancel')) {
      final b = bookings.firstWhere((b) => b['id'] == path.split('/')[2]);
      b['status'] = 'CANCELLED';
      b['cancellable'] = false;
      return _json(b);
    }
    if (path.startsWith('booking/bookings/')) {
      return _json(bookings.firstWhere((b) => b['id'] == path.split('/')[2]));
    }
    return http.Response('not found', 404);
  }
}

Future<BookingServices> _services(_FakeBackend backend) async {
  final auth = AuthRepository(
    gateway: _Gateway(),
    vault: _Vault(),
    apiBase: Uri.parse('https://api.example.test/api/v1/'),
    client: MockClient(backend.handle),
  );
  await auth.signIn(AuthTokens('access', 'refresh', null,
      DateTime.now().add(const Duration(minutes: 5))));
  addTearDown(auth.dispose);
  return BookingServices(
    api: BookingApi(
        baseUri: Uri.parse('https://api.example.test/api/v1/'),
        auth: auth,
        client: MockClient(backend.handle)),
    auth: auth,
  );
}

Future<void> _show(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(MaterialApp(home: home));
  await tester.pumpAndSettle();
}

Future<void> _openFlow(WidgetTester tester) async {
  await tester.tap(find.text('Барбершопы'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Тест Барбершоп'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Записаться'));
  await tester.pumpAndSettle();
}

void main() {
  test('time and duration formatting uses the venue wall clock', () {
    expect(formatDuration(45), '45 мин');
    expect(formatDuration(60), '1 ч');
    expect(formatDuration(75), '1 ч 15 мин');
    final t = parseVenueTime('2026-11-22T14:30:00+05:00');
    expect(formatClock(t), '14:30');
    expect(formatDay(t), 'вс, 22 ноября');
    expect(() => parseVenueTime('bad'), throwsFormatException);
  });

  test('platform snapshot reads bookingEnabled and defaults to off', () {
    final base = {
      'releaseStage': 'FOUNDATION',
      'marketplaceEnabled': true,
      'oidcIssuerConfigured': false,
      'aiEnabled': false
    };
    expect(PlatformSnapshot.fromJson(base).bookingEnabled, isFalse);
    expect(
        PlatformSnapshot.fromJson({...base, 'bookingEnabled': true})
            .bookingEnabled,
        isTrue);
  });

  testWidgets('customer books a barber, sees it after a restart and cancels it',
      (tester) async {
    final backend = _FakeBackend();
    final services = await _services(backend);
    await _show(tester, ServicesHomeScreen(services: services));
    expect(find.text('Уборка'), findsOneWidget);
    expect(find.text('Скоро'), findsOneWidget);

    await _openFlow(tester);
    expect(find.text('Запись'), findsWidgets);
    expect(find.text('10:00'), findsOneWidget);
    await tester.tap(find.text('10:15'));
    await tester.pump();
    expect(find.text('Ваша запись'), findsOneWidget);
    expect(find.text('Мастер: Арман'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Записаться ·'));
    await tester.pumpAndSettle();

    expect(find.text('Вы записаны!'), findsOneWidget);
    expect(backend.bookings, hasLength(1));
    expect(backend.bookings.single['startsAt'], contains('T10:15:00+05:00'));
    expect(find.text('Подтверждена'), findsWidgets);

    // "Restart": a brand-new app state restores the history from the server.
    final restarted = await _services(backend);
    await _show(tester, Scaffold(body: BookingsList(services: restarted)));
    expect(find.text('Предстоящие'), findsOneWidget);
    expect(find.textContaining('Тест Барбершоп'), findsOneWidget);
    await tester.tap(find.textContaining('Тест Барбершоп'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отменить запись'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Отменить запись'));
    await tester.pumpAndSettle();
    expect(backend.bookings.single['status'], 'CANCELLED');
    expect(find.text('Отменена'), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('История'), findsOneWidget);
  });

  testWidgets(
      'a slot taken by someone else shows a message and reloads the times',
      (tester) async {
    final backend = _FakeBackend()..slotTakenOnBook = true;
    final services = await _services(backend);
    await _show(tester, ServicesHomeScreen(services: services));
    await _openFlow(tester);
    final before = backend.slotRequests;
    await tester.tap(find.text('11:00'));
    await tester.pump();
    await tester.drag(find.byType(ListView).last, const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Записаться ·'));
    await tester.pumpAndSettle();
    expect(find.text('Это время только что заняли. Выберите другое.'),
        findsOneWidget);
    expect(backend.bookings, isEmpty);
    expect(backend.slotRequests, greaterThan(before));
  });

  testWidgets('history shows an empty state and an offline error with retry',
      (tester) async {
    final backend = _FakeBackend();
    final services = await _services(backend);
    await _show(tester,
        Scaffold(body: BookingsList(key: UniqueKey(), services: services)));
    expect(find.text('Записей пока нет'), findsOneWidget);
    backend.offline = true;
    await _show(tester,
        Scaffold(body: BookingsList(key: UniqueKey(), services: services)));
    expect(find.text('Не удалось загрузить записи'), findsOneWidget);
    backend.offline = false;
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();
    expect(find.text('Записей пока нет'), findsOneWidget);
  });
}
