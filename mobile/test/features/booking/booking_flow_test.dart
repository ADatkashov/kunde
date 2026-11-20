import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_mobile/features/booking/booking_services.dart';
import 'package:kunde_mobile/features/booking/data/booking_api.dart';
import 'package:kunde_mobile/features/booking/data/booking_models.dart';
import 'package:kunde_mobile/features/booking/presentation/bookings_list.dart';
import 'package:kunde_mobile/features/booking/presentation/category_screens.dart';
import 'package:kunde_mobile/features/booking/presentation/services_home_screen.dart';
import 'package:kunde_mobile/core/localization/kunde_localizations.dart';
import 'package:kunde_mobile/features/health/health_home_screen.dart';
import 'package:kunde_mobile/features/home/data/kunde_api.dart';
import 'package:kunde_mobile/features/home/data/platform_snapshot.dart';
import 'package:kunde_mobile/features/home/presentation/home_screen.dart';
import 'package:kunde_mobile/features/home/presentation/super_app_widgets.dart';
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
const _healthVenueId = '77777777-7777-7777-7777-777777777777';
const _cleanVenueId = '44444444-4444-4444-4444-444444444444';
const _cleanServiceId = '55555555-5555-5555-5555-555555555555';
const _cleanCrewId = '66666666-6666-6666-6666-666666666666';

final _cleanVenue = {
  'id': _cleanVenueId,
  'slug': 'home-clean-test',
  'category': 'CLEANING',
  'name': 'Тест Уборка',
  'description': 'Вымышленная служба',
  'addressText': 'Выезд по адресу клиента',
  'emoji': '🧹',
  'tone': 'green',
  'open': true,
  'synthetic': true,
  'fromPriceMinor': 800000,
};

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

final _healthVenue = {
  ..._venue,
  'id': _healthVenueId,
  'category': 'HEALTH',
  'name': 'ДЕМО · Контур',
};

/// In-memory stand-in for the booking backend: slots per date, one master, persisted bookings across app restarts.
class _FakeBackend {
  final bookings = <Map<String, dynamic>>[];
  final keys = <String, String>{};
  bool offline = false;
  bool slotTakenOnBook = false;
  int slotRequests = 0;
  Uri? lastHealthSearch;
  Map<String, dynamic>? lastCleaningRequest;

  http.Response _json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status,
          headers: {'content-type': 'application/json; charset=utf-8'});

  Future<http.Response> handle(http.Request request) async {
    if (offline) throw http.ClientException('offline');
    final path = request.url.path.replaceFirst('/api/v1/', '');
    final body = request.body.isEmpty
        ? null
        : jsonDecode(request.body) as Map<String, dynamic>;
    if (path == 'booking/health/venues') {
      lastHealthSearch = request.url;
      return _json([_healthVenue]);
    }
    if (path == 'booking/venues') {
      return _json(request.url.queryParameters['category'] == 'CLEANING'
          ? [_cleanVenue]
          : [_venue]);
    }
    if (path == 'booking/venues/$_cleanVenueId') {
      return _json({
        'venue': _cleanVenue,
        'services': [
          {
            'id': _cleanServiceId,
            'name': 'Генеральная уборка',
            'description': 'Глубокая уборка',
            'durationMinutes': 180,
            'priceMinor': 600000,
            'available': true,
            'pricePerSqmMinor': 45000,
            'minAreaSqm': 20,
            'maxAreaSqm': 150
          }
        ],
        'masters': [
          {
            'id': _cleanCrewId,
            'name': 'Бригада «Север»',
            'bio': 'Синтетическая',
            'emoji': '🧽',
            'tone': 'green',
            'serviceIds': [_cleanServiceId]
          }
        ],
      });
    }
    if (path == 'booking/venues/$_venueId' ||
        path == 'booking/venues/$_healthVenueId') {
      return _json({
        'venue': path.endsWith(_healthVenueId) ? _healthVenue : _venue,
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
            'masterId':
                request.url.queryParameters['serviceId'] == _cleanServiceId
                    ? _cleanCrewId
                    : _masterId,
            'masterName':
                request.url.queryParameters['serviceId'] == _cleanServiceId
                    ? 'Бригада «Север»'
                    : 'Арман'
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
      if (body['venueId'] == _cleanVenueId) {
        lastCleaningRequest = body;
        final area = body['areaSqm'] as int;
        final record = {
          'id': 'cccccccc-0000-0000-0000-00000000000${bookings.length + 1}',
          'venueId': _cleanVenueId,
          'venueName': 'Тест Уборка',
          'venueAddress': 'Выезд по адресу клиента',
          'serviceName': 'Генеральная уборка',
          'durationMinutes': 180,
          'masterId': _cleanCrewId,
          'masterName': 'Бригада «Север»',
          'startsAt': starts,
          'endsAt': '${starts.substring(0, 11)}13:00:00+05:00',
          'priceMinor': 600000 + 45000 * area,
          'currency': 'KZT',
          'status': 'CONFIRMED',
          'confirmation': 'DEV_MOCK',
          'comment': body['comment'],
          'cancellable': true,
          'category': 'CLEANING',
          'addressText': body['addressText'],
          'areaSqm': area,
        };
        bookings.insert(0, record);
        keys[key] = record['id'] as String;
        return _json(record, 201);
      }
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

  testWidgets(
      'Health directions and text search reach the real client contract',
      (tester) async {
    final backend = _FakeBackend();
    final services = await _services(backend);
    await _show(tester, HealthHomeScreen(services: services));

    await tester.tap(find.text('Врачи'));
    await tester.pumpAndSettle();
    expect(backend.lastHealthSearch?.queryParameters['direction'], 'DOCTORS');

    await tester.enterText(find.byType(TextField), 'Контур');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(backend.lastHealthSearch?.queryParameters['q'], 'Контур');
    expect(find.text('ДЕМО · Контур'), findsOneWidget);
  });

  testWidgets('Health specialist opens at 200% text in dark theme',
      (tester) async {
    final services = await _services(_FakeBackend());
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      localizationsDelegates: KundeLocalizations.localizationsDelegates,
      supportedLocales: KundeLocalizations.supportedLocales,
      locale: const Locale('en'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2)),
        child: child!,
      ),
      home: HealthHomeScreen(services: services),
    ));
    await tester.pumpAndSettle();
    final venue = find.text('ДЕМО · Контур');
    await tester.scrollUntilVisible(venue.hitTestable(), 280,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(venue);
    await tester.pumpAndSettle();
    final specialist = find.text('Арман');
    await tester.scrollUntilVisible(specialist.hitTestable(), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(specialist);
    await tester.pumpAndSettle();
    expect(find.text('Specialist'), findsOneWidget);
    expect(find.text('Synthetic profile'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('customer books a barber, sees it after a restart and cancels it',
      (tester) async {
    final backend = _FakeBackend();
    final services = await _services(backend);
    await _show(tester, BeautyCategoryScreen(services: services));
    // Cleaning is not shown in «Красота»; barbershops are.
    expect(find.text('Уборка'), findsNothing);
    expect(find.text('Барбершопы'), findsOneWidget);

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
    await _show(tester, BeautyCategoryScreen(services: services));
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

  testWidgets(
      'categories keep barbershops and cleaning apart; the catalog lists both',
      (tester) async {
    final services = await _services(_FakeBackend());
    await _show(tester, HomeServicesCategoryScreen(services: services));
    expect(find.text('Уборка'), findsOneWidget);
    expect(find.text('Барбершопы'), findsNothing);
    await _show(tester, ServicesHomeScreen(services: services));
    expect(find.text('Красота'), findsOneWidget);
    expect(find.text('Дом и быт'), findsOneWidget);
    expect(find.text('Барбершопы'), findsOneWidget);
    expect(find.text('Уборка'), findsOneWidget);
  });

  testWidgets(
      'customer orders cleaning: validation, estimate, request, history after restart, cancel',
      (tester) async {
    final backend = _FakeBackend();
    final services = await _services(backend);
    await _show(tester, HomeServicesCategoryScreen(services: services));
    await tester.tap(find.text('Уборка'));
    await tester.pumpAndSettle();
    expect(find.text('Генеральная уборка'), findsOneWidget);
    // Estimate needs a valid area; an out-of-range area is refused locally.
    expect(find.byKey(const ValueKey('cleaning-estimate')), findsOneWidget);
    final area = find.widgetWithText(TextField, 'Площадь, м²');
    await tester.enterText(area, '10');
    await tester.pump();
    expect(find.text('Укажите площадь от 20 до 150 м²'), findsOneWidget);
    await tester.enterText(area, '60');
    await tester.pump();
    // 6 000 + 450 x 60 m² = 33 000 tenge, computed with the same formula as the server.
    expect(find.text(formatTenge(3300000)), findsWidgets);
    await tester.tap(find.text('10:15'));
    await tester.pump();
    // A too short address is refused and nothing is sent.
    await tester.enterText(find.widgetWithText(TextField, 'Адрес'), 'ул');
    await tester.drag(find.byType(ListView).last, const Offset(0, -900));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Оформить заявку'));
    await tester.pumpAndSettle();
    expect(backend.bookings, isEmpty);
    await tester.enterText(find.widgetWithText(TextField, 'Адрес'),
        'Алматы, ул. Тестовая 1, кв. 5');
    await tester.pump();
    await tester.tap(find.textContaining('Оформить заявку'));
    await tester.pumpAndSettle();

    expect(find.text('Заявка оформлена!'), findsOneWidget);
    expect(backend.lastCleaningRequest!['areaSqm'], 60);
    expect(backend.lastCleaningRequest!['addressText'],
        'Алматы, ул. Тестовая 1, кв. 5');
    expect(backend.bookings.single['priceMinor'], 3300000);
    expect(find.text('Алматы, ул. Тестовая 1, кв. 5'), findsOneWidget);
    expect(find.text('Площадь: 60 м²'), findsOneWidget);

    // "Restart": the history is restored from the server with the cleaning details.
    final restarted = await _services(backend);
    await _show(tester, Scaffold(body: BookingsList(services: restarted)));
    expect(find.textContaining('Тест Уборка'), findsOneWidget);
    await tester.tap(find.textContaining('Тест Уборка'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отменить заявку'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Отменить запись'));
    await tester.pumpAndSettle();
    expect(backend.bookings.single['status'], 'CANCELLED');
    expect(find.text('Отменена'), findsWidgets);
  });

  testWidgets(
      'home categories: Красота opens barbershops, Дом и быт opens cleaning',
      (tester) async {
    final services = await _services(_FakeBackend());
    final api = KundeApi(
        baseUri: Uri.parse('https://api.example.test/api/v1/'),
        client: MockClient((_) async => http.Response(
            jsonEncode({
              'releaseStage': 'FOUNDATION',
              'marketplaceEnabled': true,
              'oidcIssuerConfigured': false,
              'aiEnabled': false,
              'bookingEnabled': true,
            }),
            200)));
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        localizationsDelegates: KundeLocalizations.localizationsDelegates,
        supportedLocales: KundeLocalizations.supportedLocales,
        locale: const Locale('ru'),
        home: HomeScreen(api: api, booking: services)));
    await tester.pumpAndSettle();
    Finder category(String label) => find.descendant(
          of: find.byType(CategoryGrid),
          matching: find.text(label),
        );

    await tester.tap(category('Красота'));
    await tester.pumpAndSettle();
    expect(find.text('Барбершопы'), findsOneWidget);
    expect(find.text('Уборка'), findsNothing);
    Navigator.of(tester.element(find.text('Барбершопы'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(category('Дом и быт'));
    await tester.pumpAndSettle();
    expect(find.text('Уборка'), findsOneWidget);
    expect(find.text('Барбершопы'), findsNothing);
  });
}
