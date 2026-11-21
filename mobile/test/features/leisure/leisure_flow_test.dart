import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_mobile/core/localization/kunde_localizations.dart';
import 'package:kunde_mobile/features/identity/auth_repository.dart';
import 'package:kunde_mobile/features/leisure/data/leisure_api.dart';
import 'package:kunde_mobile/features/leisure/data/leisure_models.dart';
import 'package:kunde_mobile/features/leisure/leisure_services.dart';
import 'package:kunde_mobile/features/leisure/presentation/leisure_event_screen.dart';
import 'package:kunde_mobile/features/leisure/presentation/leisure_home_screen.dart';
import 'package:kunde_mobile/features/leisure/presentation/leisure_orders_screen.dart';
import 'package:qr_flutter/qr_flutter.dart';

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

const _eventId = '11111111-1111-1111-1111-111111111111';
const _sessionId = '22222222-2222-2222-2222-222222222222';
const _stdType = '33333333-3333-3333-3333-333333333333';
const _orderId = '44444444-4444-4444-4444-444444444444';

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}'
    'T${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:00+05:00';

/// In-memory Leisure backend with the contract of the real API: server-side prices, holds, idempotent orders, seat conflicts.
class _FakeLeisure {
  bool enabled = true;
  bool offline = false;
  bool seatTakenOnHold = false;
  final orders = <Map<String, dynamic>>[];
  final keys = <String, String>{};
  int placeCalls = 0;
  String? lastHoldBody;
  late final DateTime start = DateTime.now()
      .toUtc()
      .add(const Duration(hours: 5, days: 1))
      .copyWith(
          hour: 19, minute: 30, second: 0, millisecond: 0, microsecond: 0);

  http.Response _json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status,
          headers: {'content-type': 'application/json; charset=utf-8'});

  Map<String, dynamic> get _card => {
        'id': _eventId,
        'title': 'Демо-фильм «Ночной экспресс»',
        'venueId': 'v',
        'venueName': 'Демо-кинозал',
        'district': 'Бостандыкский',
        'address': 'ул. Тестовая, 1',
        'categoryCode': 'CINEMA',
        'bookingType': 'SEAT_MAP',
        'photoUrl': null,
        'minPriceMinor': 200000,
        'currency': 'KZT',
        'minAge': 12,
        'familyFriendly': false,
        'rating': null,
        'reviewCount': 0,
        'nextSessionAt': _iso(start),
        'nextSessionId': _sessionId,
        'nextSessionFree': 58,
        'distanceKm': null,
      };

  Map<String, dynamic> _order(String status) => {
        'id': _orderId,
        'status': status,
        'phase': 'UPCOMING',
        'eventId': _eventId,
        'eventTitle': 'Демо-фильм «Ночной экспресс»',
        'categoryCode': 'CINEMA',
        'bookingType': 'SEAT_MAP',
        'venueId': 'v',
        'venueName': 'Демо-кинозал',
        'venueAddress': 'ул. Тестовая, 1',
        'photoUrl': null,
        'sessionId': _sessionId,
        'startsAt': _iso(start),
        'endsAt': _iso(start.add(const Duration(hours: 2))),
        'guests': 2,
        'totalMinor': 400000,
        'currency': 'KZT',
        'paymentMethod': 'TEST_CARD',
        'payment': {
          'method': 'TEST_CARD',
          'status': status == 'CANCELLED' ? 'TEST_REFUNDED' : 'TEST_CAPTURED',
          'refundedMinor': status == 'CANCELLED' ? 400000 : 0,
          'mode': 'DEV_TEST'
        },
        'cancellable': status != 'CANCELLED',
        'cancelUntil': _iso(start.subtract(const Duration(hours: 2))),
        'cancelledBy': status == 'CANCELLED' ? 'CUSTOMER' : null,
        'cancelReason': null,
        'createdAt': _iso(DateTime.now()),
        'rules': 'Вход по билету.',
        'minAge': 12,
        'reviewed': false,
        'canReview': false,
        'tickets': [
          for (final seat in ['D5', 'D6'])
            {
              'id': seat == 'D5'
                  ? 'aaaaaaaa-0000-0000-0000-000000000001'
                  : 'bbbbbbbb-0000-0000-0000-000000000002',
              'status': status == 'CANCELLED' ? 'CANCELLED' : 'VALID',
              'ticketType': 'Стандарт',
              'seat': seat,
              'admits': 1,
              'priceMinor': 200000,
              'qr': status == 'CANCELLED'
                  ? null
                  : 'KT1.${seat == 'D5' ? 'aaaaaaaa-0000-0000-0000-000000000001' : 'bbbbbbbb-0000-0000-0000-000000000002'}.0123456789abcdef0123456789abcdef',
            }
        ],
        'timeline': [],
      };

  final requested = <String>[];

  Future<http.Response> handle(http.Request request) async {
    if (offline) throw http.ClientException('offline');
    var path = request.url.path.replaceFirst('/api/v1/', '');
    requested.add(path);
    // Events is the other product's public catalogue over the same engine: same fixtures, other paths.
    if (path == 'events' || path.startsWith('events/')) {
      path = path == 'events/categories'
          ? 'leisure/categories'
          : path == 'events/home'
              ? 'leisure/home'
              : path == 'events'
                  ? 'leisure/events'
                  : path.replaceFirst('events/', 'leisure/events/');
    }
    final body = request.body.isEmpty
        ? null
        : jsonDecode(request.body) as Map<String, dynamic>;
    if (path == 'leisure/categories') {
      return _json(enabled
          ? [
              {
                'code': 'CINEMA',
                'nameRu': 'Кинотеатры',
                'nameKk': 'Кинотеатрлар',
                'nameEn': 'Cinemas',
                'bookingType': 'SEAT_MAP',
                'familyFriendly': true,
                'enabled': true
              },
              {
                'code': 'BOWLING',
                'nameRu': 'Боулинг',
                'nameKk': 'Боулинг',
                'nameEn': 'Bowling',
                'bookingType': 'TIME_SLOT',
                'familyFriendly': true,
                'enabled': true
              },
            ]
          : []);
    }
    if (path == 'leisure/home') {
      return _json({
        'today': enabled ? [_card] : [],
        'weekend': [],
        'family': [],
        'popular': enabled ? [_card] : []
      });
    }
    if (path == 'leisure/events') return _json(enabled ? [_card] : []);
    if (path == 'leisure/favorites') return _json(<String>[]);
    if (path == 'leisure/events/$_eventId') {
      return _json({
        'id': _eventId,
        'title': 'Демо-фильм «Ночной экспресс»',
        'description': 'Вымышленный фильм.',
        'photos': [],
        'category': {
          'code': 'CINEMA',
          'nameRu': 'Кинотеатры',
          'nameKk': 'Кинотеатрлар',
          'nameEn': 'Cinemas',
          'bookingType': 'SEAT_MAP',
          'familyFriendly': true,
          'enabled': true
        },
        'bookingType': 'SEAT_MAP',
        'durationMinutes': 120,
        'minAge': 12,
        'familyFriendly': false,
        'maxGuests': 8,
        'confirmation': 'AUTO',
        'venue': {
          'id': 'v',
          'name': 'Демо-кинозал',
          'description': '',
          'address': 'ул. Тестовая, 1',
          'district': 'Бостандыкский',
          'photos': [],
          'rules': 'Вход по билету.',
          'cancellationHours': 2
        },
        'organizer': 'Демо-партнёр',
        'ticketTypes': [
          {
            'id': _stdType,
            'name': 'Стандарт',
            'priceMinor': 200000,
            'currency': 'KZT',
            'pricing': 'PER_TICKET',
            'zone': 'STANDARD'
          }
        ],
        'rating': null,
        'reviewCount': 0,
        'bookable': enabled,
        'demo': true,
      });
    }
    if (path == 'leisure/events/$_eventId/sessions') {
      return _json([
        {
          'id': _sessionId,
          'startsAt': _iso(start),
          'endsAt': _iso(start.add(const Duration(hours: 2))),
          'capacity': 60,
          'free': 58,
          'fromPriceMinor': 200000
        }
      ]);
    }
    if (path == 'leisure/sessions/$_sessionId/seats') {
      return _json([
        for (final row in ['A', 'B', 'C', 'D'])
          for (var n = 1; n <= 6; n++)
            {
              'id': 'seat-$row$n',
              'row': row,
              'number': n,
              'zone': 'STANDARD',
              'status': row == 'A' && n == 1 ? 'SOLD' : 'FREE',
              'priceMinor': 200000
            }
      ]);
    }
    if (path == 'leisure/sessions/$_sessionId/holds') {
      lastHoldBody = request.body;
      if (seatTakenOnHold) {
        return _json({'code': 'SEAT_TAKEN', 'message': 'taken'}, 409);
      }
      final lines = (body!['lines'] as List).cast<Map<String, dynamic>>();
      final seatIds = [
        for (final l in lines)
          ...((l['seatIds'] as List?) ?? const []).cast<String>()
      ];
      return _json({
        'id': '55555555-5555-5555-5555-555555555555',
        'sessionId': _sessionId,
        'guests': seatIds.length,
        'totalMinor': 200000 * seatIds.length,
        'currency': 'KZT',
        'expiresAt': DateTime.now()
            .add(const Duration(minutes: 10))
            .toUtc()
            .toIso8601String(),
        'lines': [
          for (final s in seatIds)
            {
              'ticketTypeId': _stdType,
              'ticketType': 'Стандарт',
              'seatId': s,
              'seat': s.replaceFirst('seat-', ''),
              'unitPriceMinor': 200000
            }
        ],
      }, 201);
    }
    if (path.startsWith('leisure/holds/') && request.method == 'DELETE') {
      return http.Response('', 204);
    }
    if (path == 'leisure/orders' && request.method == 'POST') {
      placeCalls++;
      final key = request.headers['Idempotency-Key']!;
      final repeated = keys.containsKey(key);
      keys[key] = _orderId;
      if (!repeated) orders.add(_order('CONFIRMED'));
      return _json(_order('CONFIRMED'), repeated ? 200 : 201);
    }
    if (path == 'leisure/orders' && request.method == 'GET') {
      final scope = request.url.queryParameters['scope'];
      return _json([
        for (final o in orders)
          if ((scope == 'cancelled') == (o['status'] == 'CANCELLED') &&
              scope != 'completed')
            o
      ]);
    }
    if (path == 'leisure/orders/$_orderId' && request.method == 'GET') {
      return _json(orders.isEmpty ? _order('CONFIRMED') : orders.first);
    }
    if (path == 'leisure/orders/$_orderId/cancel') {
      orders
        ..clear()
        ..add(_order('CANCELLED'));
      return _json(_order('CANCELLED'));
    }
    return _json({'code': 'NOT_FOUND'}, 404);
  }
}

Future<LeisureServices> _services(_FakeLeisure backend) async {
  final auth = AuthRepository(
      gateway: _Gateway(),
      vault: _Vault(),
      apiBase: Uri.parse('https://api.example.test/api/v1/'),
      client: MockClient(backend.handle));
  await auth.signIn(AuthTokens('access', 'refresh', null,
      DateTime.now().add(const Duration(minutes: 5))));
  addTearDown(auth.dispose);
  return LeisureServices(
      api: LeisureApi(
          baseUri: Uri.parse('https://api.example.test/api/v1/'),
          auth: auth,
          client: MockClient(backend.handle)),
      auth: auth);
}

Widget _app(Widget home,
        {Locale locale = const Locale('ru'),
        TextScaler scaler = TextScaler.noScaling,
        ThemeMode mode = ThemeMode.light}) =>
    MaterialApp(
      locale: locale,
      themeMode: mode,
      darkTheme: ThemeData.dark(useMaterial3: true),
      supportedLocales: KundeLocalizations.supportedLocales,
      localizationsDelegates: KundeLocalizations.localizationsDelegates,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: scaler),
          child: child!),
      home: home,
    );

void _phone(WidgetTester tester, {double width = 390, double height = 844}) {
  tester.view.physicalSize = Size(width * 2, height * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

void main() {
  test('booking types parse and price kinds follow them', () {
    expect(BookingType.parse('SEAT_MAP'), BookingType.seatMap);
    expect(BookingType.parse('TIME_SLOT').perBooking, isTrue);
    expect(BookingType.parse('PRIVATE_SESSION').perBooking, isTrue);
    expect(BookingType.parse('CAPACITY').perBooking, isFalse);
    expect(
        venueTime('2026-11-21T19:30:00+05:00'), DateTime(2026, 11, 21, 19, 30));
    expect(
        Ticket.fromJson({
          'id': 'abcdef12-0000-0000-0000-000000000000',
          'status': 'VALID',
          'ticketType': 'X',
          'admits': 1,
          'priceMinor': 1
        }).shortId,
        'ABCDEF12');
  });

  testWidgets('home shows server categories and sections, nothing invented',
      (tester) async {
    _phone(tester);
    final services = await _services(_FakeLeisure());
    await tester.pumpWidget(_app(LeisureHomeScreen(services: services)));
    await tester.pumpAndSettle();
    expect(find.text('Досуг и развлечения'), findsOneWidget);
    expect(find.text('Кинотеатры'), findsOneWidget);
    expect(find.text('Боулинг'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Популярное'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('Демо-фильм'), findsWidgets);
    expect(find.byIcon(Icons.star_rounded),
        findsNothing); // no rating without real reviews
  });

  testWidgets(
      'Events product reads /events, shows its own title and the cinema',
      (tester) async {
    _phone(tester);
    final backend = _FakeLeisure();
    final services =
        (await _services(backend)).forProduct(LeisureProduct.events);
    expect(services.isEvents, isTrue);
    await tester.pumpWidget(_app(LeisureHomeScreen(services: services)));
    await tester.pumpAndSettle();
    expect(find.text('События'), findsOneWidget);
    expect(find.text('Досуг и развлечения'), findsNothing);
    expect(find.text('Кинотеатры'), findsOneWidget);
    expect(
        backend.requested, containsAll(['events/categories', 'events/home']));
    expect(backend.requested, isNot(contains('leisure/categories')));
    // opening a card reads the event through /events, the seats and purchase stay on the shared engine
    await tester.scrollUntilVisible(find.text('Популярное'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.textContaining('Демо-фильм').first);
    await tester.pumpAndSettle();
    expect(backend.requested, contains('events/$_eventId'));
  });

  testWidgets('Leisure product keeps reading /leisure', (tester) async {
    _phone(tester);
    final backend = _FakeLeisure();
    await tester.pumpWidget(
        _app(LeisureHomeScreen(services: await _services(backend))));
    await tester.pumpAndSettle();
    expect(backend.requested, contains('leisure/categories'));
    expect(backend.requested.any((p) => p.startsWith('events')), isFalse);
  });

  testWidgets(
      'switch off: the server returns no categories and the home says so',
      (tester) async {
    _phone(tester);
    final backend = _FakeLeisure()..enabled = false;
    await tester.pumpWidget(
        _app(LeisureHomeScreen(services: await _services(backend))));
    await tester.pumpAndSettle();
    expect(find.text('Досуг временно недоступен'), findsOneWidget);
  });

  testWidgets('offline home recovers with retry', (tester) async {
    _phone(tester);
    final backend = _FakeLeisure()..offline = true;
    await tester.pumpWidget(
        _app(LeisureHomeScreen(services: await _services(backend))));
    await tester.pumpAndSettle();
    expect(find.textContaining('Нет соединения'), findsWidgets);
    backend.offline = false;
    await tester.tap(find.text('Повторить').first);
    await tester.pumpAndSettle();
    expect(find.text('Кинотеатры'), findsOneWidget);
  });

  testWidgets(
      'seat purchase: details -> session -> seats -> summary -> payment -> QR ticket, retried safely',
      (tester) async {
    _phone(tester, height: 1000);
    final backend = _FakeLeisure();
    final services = await _services(backend);
    await tester.pumpWidget(
        _app(LeisureEventScreen(services: services, eventId: _eventId)));
    await tester.pumpAndSettle();
    expect(find.text('Демо-фильм «Ночной экспресс»'), findsWidgets);
    // the price is visible before any action; the booking button needs a session first
    expect(find.textContaining('от 2'), findsWidgets);
    await tester.tap(find.text('19:30'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Выбрать места'));
    await tester.pumpAndSettle();
    expect(find.text('Выбор мест'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel(RegExp('Место D5')));
    await tester.tap(find.bySemanticsLabel(RegExp('Место D6')));
    await tester.pump();
    expect(find.textContaining('Выбрано: 2'), findsOneWidget);
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();
    expect(backend.lastHoldBody, contains('seat-D5'));
    expect(find.text('Бронирование'), findsOneWidget);
    expect(find.textContaining(formatTenge(400000)), findsWidgets);
    // 12+: the age confirmation is required before payment
    expect(
        tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed,
        isNull);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();
    expect(find.text('Оплата'), findsOneWidget);
    expect(find.text('Тестовая карта (DEV)'), findsOneWidget);
    expect(find.textContaining('Apple'),
        findsNothing); // no payment method that the backend does not have
    // connection lost: the choice is kept and the retry reuses the same key
    backend.offline = true;
    await tester.tap(find.textContaining('Оплатить'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Нет соединения'), findsOneWidget);
    backend.offline = false;
    await tester.tap(find.textContaining('Оплатить'));
    await tester.pumpAndSettle();
    expect(backend.placeCalls, 1);
    expect(find.text('Мой билет'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.textContaining('KND-AAAAAAAA'), findsOneWidget);
    expect(find.textContaining('Тестовая карта'), findsWidgets);
    // cancel: the order moves to the cancelled state and shows the refund
    await tester.ensureVisible(find.text('Отменить бронь'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отменить бронь'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Отменить бронь'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Возврат оформлен'), findsOneWidget);
    expect(find.byType(QrImageView), findsNothing);
  });

  testWidgets('a seat taken meanwhile is reported and the plan reloads',
      (tester) async {
    _phone(tester, height: 1000);
    final backend = _FakeLeisure()..seatTakenOnHold = true;
    await tester.pumpWidget(_app(LeisureEventScreen(
        services: await _services(backend), eventId: _eventId)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('19:30'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Выбрать места'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel(RegExp('Место B2')));
    await tester.pump();
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();
    expect(find.textContaining('только что заняли'), findsOneWidget);
    expect(find.textContaining('Выбрано: 1'), findsNothing);
  });

  testWidgets('my entertainment lists bookings by tab', (tester) async {
    _phone(tester);
    final backend = _FakeLeisure();
    backend.orders.add(backend._order('CONFIRMED'));
    await tester.pumpWidget(
        _app(LeisureOrdersScreen(services: await _services(backend))));
    await tester.pumpAndSettle();
    expect(find.text('Предстоящие'), findsOneWidget);
    expect(find.text('Демо-фильм «Ночной экспресс»'), findsOneWidget);
    await tester.tap(find.text('Отменённые'));
    await tester.pumpAndSettle();
    expect(find.text('Здесь пока пусто'), findsOneWidget);
  });

  for (final locale in ['kk', 'en']) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
          'home and details render in $locale at text x$scale without overflow',
          (tester) async {
        _phone(tester, width: 320, height: 700);
        final services = await _services(_FakeLeisure());
        await tester.pumpWidget(_app(LeisureHomeScreen(services: services),
            locale: Locale(locale),
            scaler: TextScaler.linear(scale),
            mode: ThemeMode.dark));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(_app(
            LeisureEventScreen(services: services, eventId: _eventId),
            locale: Locale(locale),
            scaler: TextScaler.linear(scale)));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
