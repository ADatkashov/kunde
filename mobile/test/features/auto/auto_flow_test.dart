import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_mobile/core/localization/kunde_localizations.dart';
import 'package:kunde_mobile/features/auto/auto_services.dart';
import 'package:kunde_mobile/features/auto/data/auto_api.dart';
import 'package:kunde_mobile/features/auto/presentation/auto_bookings_screen.dart';
import 'package:kunde_mobile/features/auto/presentation/auto_home_screen.dart';
import 'package:kunde_mobile/features/auto/presentation/vehicles_screen.dart';
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

final _venue = {
  'id': _venueId,
  'name': 'Тестовое СТО',
  'description': 'Вымышленный сервис',
  'addressText': 'Алматы, тестовый адрес',
  'open': true,
  'synthetic': true,
  'fromPriceMinor': 1200000,
  'categories': ['OIL_CHANGE'],
};

/// In-memory Auto backend: vehicles, server-priced quotes, idempotent booking, cancel.
class _FakeAuto {
  final vehicles = <Map<String, dynamic>>[];
  final bookings = <Map<String, dynamic>>[];
  final keys = <String, String>{};
  bool offline = false;
  bool slotTakenOnQuote = false;
  String? lastQuery;
  int quotes = 0;

  http.Response _json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status,
          headers: {'content-type': 'application/json; charset=utf-8'});

  Future<http.Response> handle(http.Request request) async {
    if (offline) throw http.ClientException('offline');
    final path = request.url.path.replaceFirst('/api/v1/', '');
    final body = request.body.isEmpty
        ? null
        : jsonDecode(request.body) as Map<String, dynamic>;
    if (path == 'auto/categories') {
      return _json([
        {
          'code': 'OIL_CHANGE',
          'nameRu': 'Замена масла',
          'nameKk': 'Май ауыстыру',
          'nameEn': 'Oil change',
          'mobile': false,
          'enabled': true
        }
      ]);
    }
    if (path == 'auto/venues') {
      lastQuery = request.url.queryParameters['q'];
      final q = (lastQuery ?? '').toLowerCase();
      return _json(q.isNotEmpty && !'тестовое'.contains(q) ? [] : [_venue]);
    }
    if (path == 'auto/venues/$_venueId') {
      return _json({
        'venue': _venue,
        'services': [
          {
            'id': _serviceId,
            'name': 'Замена масла',
            'description': 'Масло и фильтр',
            'category': 'OIL_CHANGE',
            'durationMinutes': 45,
            'priceMinor': 1200000,
            'priceKind': 'FROM',
            'conditions': 'Материалы по согласованию',
            'available': true
          }
        ],
        'cancellationTerms': 'Free cancellation until the start.'
      });
    }
    if (path == 'auto/slots') {
      final date = request.url.queryParameters['date']!;
      return _json([
        for (final t in ['10:00', '11:00'])
          {
            'startsAt': '${date}T$t:00+05:00',
            'masterId': 'p',
            'masterName': 'Пост'
          }
      ]);
    }
    if (path == 'auto/vehicles' && request.method == 'GET') {
      return _json(vehicles);
    }
    if (path == 'auto/vehicles' && request.method == 'POST') {
      if (vehicles.length >= 5) {
        return _json({'code': 'TOO_MANY_VEHICLES'}, 409);
      }
      final v = {
        'id': 'v-${vehicles.length + 1}',
        'make': body!['make'],
        'model': body['model'],
        'year': body['year'],
        'plate': body['plate'],
        'version': 0
      };
      vehicles.add(v);
      return _json(v, 201);
    }
    if (path == 'auto/quotes') {
      quotes++;
      if (slotTakenOnQuote) return _json({'code': 'SLOT_UNAVAILABLE'}, 409);
      return _json({
        'id': 'q-$quotes',
        'venueId': body!['venueId'],
        'serviceId': body['serviceId'],
        'vehicleId': body['vehicleId'],
        'startsAt': body['startsAt'],
        'durationMinutes': 45,
        'priceMinor': 1200000,
        'currency': 'KZT',
        'priceKind': 'FROM',
        'expiresAt': DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 10))
            .toIso8601String(),
        'cancellationTerms': 'Free cancellation until the start.'
      }, 201);
    }
    if (path == 'auto/bookings' && request.method == 'POST') {
      final key = request.headers['Idempotency-Key']!;
      if (keys.containsKey(key)) {
        return _json(bookings.firstWhere((b) => b['id'] == keys[key]));
      }
      final record = {
        'id': 'b-${bookings.length + 1}',
        'venueId': _venueId,
        'serviceId': _serviceId,
        'venueName': 'Тестовое СТО',
        'venueAddress': 'Алматы, тестовый адрес',
        'serviceName': 'Замена масла',
        'durationMinutes': 45,
        'vehicleId': 'v-1',
        'vehicle': 'Toyota Camry 2018',
        'startsAt': '2030-01-02T10:00:00+05:00',
        'endsAt': '2030-01-02T10:45:00+05:00',
        'priceMinor': 1200000,
        'priceKind': 'FROM',
        'currency': 'KZT',
        'status': 'CONFIRMED',
        'cancellable': true,
        'reschedulable': true,
        'timeline': [
          {'status': 'CONFIRMED'}
        ],
      };
      bookings.add(record);
      keys[key] = record['id'] as String;
      return _json(record, 201);
    }
    if (path == 'auto/bookings' && request.method == 'GET') {
      return _json(bookings);
    }
    final cancel = RegExp(r'^auto/bookings/([^/]+)/cancel$').firstMatch(path);
    if (cancel != null) {
      final b = bookings.firstWhere((b) => b['id'] == cancel[1]);
      b['status'] = 'CANCELLED';
      b['cancellable'] = false;
      b['reschedulable'] = false;
      return _json(b);
    }
    final one = RegExp(r'^auto/bookings/([^/]+)$').firstMatch(path);
    if (one != null) {
      return _json(bookings.firstWhere((b) => b['id'] == one[1]));
    }
    return _json({'code': 'NOT_FOUND'}, 404);
  }
}

Future<AutoServices> _services(_FakeAuto backend) async {
  final auth = AuthRepository(
    gateway: _Gateway(),
    vault: _Vault(),
    apiBase: Uri.parse('https://api.example.test/api/v1/'),
    client: MockClient(backend.handle),
  );
  await auth.signIn(AuthTokens('access', 'refresh', null,
      DateTime.now().add(const Duration(minutes: 5))));
  addTearDown(auth.dispose);
  return AutoServices(
    api: AutoApi(
        baseUri: Uri.parse('https://api.example.test/api/v1/'),
        auth: auth,
        client: MockClient(backend.handle)),
    auth: auth,
  );
}

Widget _app(Widget home, {Locale locale = const Locale('ru')}) => MaterialApp(
      locale: locale,
      supportedLocales: KundeLocalizations.supportedLocales,
      localizationsDelegates: KundeLocalizations.localizationsDelegates,
      home: home,
    );

void _bigScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  test('platform snapshot reads the Auto flag and defaults to off', () {
    final json = {
      'releaseStage': 'FOUNDATION',
      'marketplaceEnabled': false,
      'oidcIssuerConfigured': false,
      'aiEnabled': false,
    };
    expect(PlatformSnapshot.fromJson(json).autoEnabled, isFalse);
    expect(
        PlatformSnapshot.fromJson({...json, 'autoEnabled': true}).autoEnabled,
        isTrue);
  });

  test('API: quote carries no price, booking is idempotent, failures map',
      () async {
    final backend = _FakeAuto();
    final services = await _services(backend);
    final v = await services.api.saveVehicle(
        make: 'Toyota', model: 'Camry', year: 2018, plate: '123ABC02');
    expect(v.label, 'Toyota Camry 2018 123ABC02');
    final q = await services.api.quote(
        venueId: _venueId,
        serviceId: _serviceId,
        vehicleId: v.id,
        startsAtIso: '2030-01-02T10:00:00+05:00');
    expect(q.priceMinor, 1200000);
    expect(q.priceKind, 'FROM');
    const key = 'au-retry-key-aaaa-bbbb-cccc';
    final first = await services.api.book(quoteId: q.id, idempotencyKey: key);
    final again = await services.api.book(quoteId: q.id, idempotencyKey: key);
    expect(again.id, first.id);
    expect(backend.bookings, hasLength(1));
    backend.slotTakenOnQuote = true;
    await expectLater(
        services.api.quote(
            venueId: _venueId,
            serviceId: _serviceId,
            vehicleId: v.id,
            startsAtIso: 'x'),
        throwsA(isA<AutoException>()
            .having((e) => e.failure, 'failure', AutoFailure.slotTaken)));
    backend.offline = true;
    await expectLater(
        services.api.bookings(),
        throwsA(isA<AutoException>()
            .having((e) => e.failure, 'failure', AutoFailure.offline)));
  });

  testWidgets('catalog search filters venues and shows the empty state',
      (tester) async {
    _bigScreen(tester);
    final backend = _FakeAuto();
    final services = await _services(backend);
    await tester.pumpWidget(_app(AutoHomeScreen(services: services)));
    await tester.pumpAndSettle();
    expect(find.text('Тестовое СТО'), findsOneWidget);
    expect(find.text('Замена масла'), findsOneWidget); // category chip
    await tester.enterText(find.byType(TextField), 'нет такого');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(backend.lastQuery, 'нет такого');
    expect(find.text('Ничего не найдено'), findsOneWidget);
  });

  testWidgets('offline catalog shows an error and recovers with retry',
      (tester) async {
    _bigScreen(tester);
    final backend = _FakeAuto()..offline = true;
    final services = await _services(backend);
    await tester.pumpWidget(_app(AutoHomeScreen(services: services)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Нет связи'), findsOneWidget);
    backend.offline = false;
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();
    expect(find.text('Тестовое СТО'), findsOneWidget);
  });

  testWidgets('vehicle form validates, saves and lists a car', (tester) async {
    _bigScreen(tester);
    final backend = _FakeAuto();
    final services = await _services(backend);
    await tester.pumpWidget(_app(VehiclesScreen(services: services)));
    await tester.pumpAndSettle();
    expect(find.text('Автомобилей пока нет'), findsOneWidget);
    await tester.tap(find.text('Добавить автомобиль'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(find.text('Обязательное поле'), findsNWidgets(2));
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Toyota');
    await tester.enterText(fields.at(1), 'Camry');
    await tester.enterText(fields.at(2), '1900');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Укажите год'), findsOneWidget);
    await tester.enterText(fields.at(2), '2018');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(find.text('Toyota Camry'), findsOneWidget);
    expect(backend.vehicles, hasLength(1));
  });

  testWidgets('customer books a service, sees the server quote and cancels',
      (tester) async {
    _bigScreen(tester);
    final backend = _FakeAuto()
      ..vehicles.add({
        'id': 'v-1',
        'make': 'Toyota',
        'model': 'Camry',
        'year': 2018,
        'plate': null,
        'version': 0
      });
    final services = await _services(backend);
    await tester.pumpWidget(_app(AutoHomeScreen(services: services)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Тестовое СТО'));
    await tester.pumpAndSettle();
    expect(find.text('Цена от, итог после осмотра'), findsOneWidget);
    await tester.tap(find.text('Записаться'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Toyota Camry 2018'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10:00'));
    await tester.pumpAndSettle();
    expect(find.text('Предварительная стоимость'), findsOneWidget);
    expect(backend.quotes, 1);
    await tester.tap(find.text('Подтвердить запись'));
    await tester.pumpAndSettle();
    expect(backend.bookings, hasLength(1));
    expect(find.text('Подтверждена'), findsWidgets);
    await tester.tap(find.text('Отменить запись'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Отменить запись'));
    await tester.pumpAndSettle();
    expect(backend.bookings.single['status'], 'CANCELLED');
    expect(find.text('Отменена'), findsWidgets);
  });

  testWidgets('bookings screen separates active ones and history in English',
      (tester) async {
    _bigScreen(tester);
    final backend = _FakeAuto();
    final base = {
      'venueId': _venueId,
      'serviceId': _serviceId,
      'venueName': 'Тестовое СТО',
      'venueAddress': 'a',
      'durationMinutes': 45,
      'vehicleId': 'v-1',
      'vehicle': 'Toyota Camry 2018',
      'startsAt': '2030-01-02T10:00:00+05:00',
      'priceMinor': 1200000,
      'priceKind': 'FIXED',
      'cancellable': false,
      'reschedulable': false,
      'timeline': [],
    };
    backend.bookings.addAll([
      {
        ...base,
        'id': 'b-1',
        'serviceName': 'Active job',
        'status': 'IN_PROGRESS'
      },
      {...base, 'id': 'b-2', 'serviceName': 'Old job', 'status': 'COMPLETED'},
    ]);
    final services = await _services(backend);
    await tester.pumpWidget(_app(AutoBookingsScreen(services: services),
        locale: const Locale('en')));
    await tester.pumpAndSettle();
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Service history'), findsOneWidget);
    expect(find.textContaining('In progress'), findsOneWidget);
    expect(find.textContaining('Completed'), findsOneWidget);
  });
}
