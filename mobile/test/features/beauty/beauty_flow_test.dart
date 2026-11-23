import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_mobile/core/localization/kunde_localizations.dart';
import 'package:kunde_mobile/features/beauty/beauty_strings.dart';
import 'package:kunde_mobile/features/beauty/beauty_theme.dart';
import 'package:kunde_mobile/features/beauty/data/beauty_models.dart';
import 'package:kunde_mobile/features/beauty/presentation/beauty_home_screen.dart';
import 'package:kunde_mobile/features/beauty/presentation/beauty_widgets.dart';
import 'package:kunde_mobile/features/booking/booking_services.dart';
import 'package:kunde_mobile/features/booking/data/booking_api.dart';
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

const _lunaId = '11111111-0000-0000-0000-000000000001';
const _auraId = '11111111-0000-0000-0000-000000000002';
const _serviceId = '22222222-0000-0000-0000-000000000001';
const _masterId = '33333333-0000-0000-0000-000000000001';

Map<String, dynamic> _salon(String id, String name,
        {double? rating, int reviews = 0, int? discount, int? price}) =>
    {
      'id': id,
      'slug': name.toLowerCase().replaceAll(' ', '-'),
      'name': name,
      'addressText': 'Алматы, ул. Сатпаева, 90',
      'emoji': '💜',
      'open': true,
      'categories': ['SALONS'],
      'latitude': 43.2389,
      'longitude': 76.9286,
      'verified': true,
      'rating': rating,
      'reviewCount': reviews,
      'fromPriceMinor': price ?? 600000,
      'discountPercent': discount,
    };

final _service = {
  'id': _serviceId,
  'name': 'Окрашивание волос',
  'description': 'Профессиональное окрашивание премиум-материалами.',
  'durationMinutes': 180,
  'priceMinor': 2500000,
  'priceFrom': true,
  'categoryCode': 'HAIR',
  'tags': ['Волосы', 'Премиум'],
};

final _master = {
  'id': _masterId,
  'name': 'Алия С.',
  'bio': '',
  'specialty': 'Колорист',
  'experienceYears': 8,
  'rating': 4.9,
  'reviewCount': 12,
  'serviceIds': [_serviceId],
  'nextSlotAt': '2026-11-20T14:00:00+05:00',
};

class _Backend {
  _Backend({this.promoPercent});

  final int? promoPercent;
  Map<String, String>? lastSalonQuery;
  Map<String, dynamic>? booked;
  final favorites = <String>{};

  http.Response _json(Object body,
          {int status = 200, Map<String, String>? headers}) =>
      http.Response(jsonEncode(body), status, headers: {
        'content-type': 'application/json; charset=utf-8',
        ...?headers,
      });

  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path.replaceFirst('/api/v1/', '');
    if (path == 'beauty/categories') {
      return _json([
        for (final (code, ru, icon) in [
          ('SALONS', 'Салоны', 'storefront'),
          ('HAIR', 'Волосы', 'brush'),
        ])
          {
            'code': code,
            'nameRu': ru,
            'nameKk': ru,
            'nameEn': ru,
            'icon': icon,
            'featured': true,
          },
        {
          'code': 'MAKEUP',
          'nameRu': 'Макияж',
          'nameKk': 'Макияж',
          'nameEn': 'Makeup',
          'icon': 'palette',
          'featured': false,
        },
      ]);
    }
    if (path == 'beauty/promotions') {
      return _json({
        'maxPercent': promoPercent,
        'items': [
          if (promoPercent != null)
            {'id': 'p1', 'title': 'Скидка', 'percent': promoPercent}
        ],
      });
    }
    if (path == 'beauty/favorites') {
      return _json(favorites.toList());
    }
    if (path.startsWith('beauty/favorites/')) {
      final id = path.split('/').last;
      request.method == 'PUT' ? favorites.add(id) : favorites.remove(id);
      return http.Response('', 204);
    }
    if (path == 'beauty/salons') {
      lastSalonQuery = request.url.queryParameters;
      final salons = [
        _salon(_lunaId, 'LUNA Beauty Studio',
            rating: 4.8, reviews: 5, discount: promoPercent),
        _salon(_auraId, 'Aura Beauty', rating: 4.9, reviews: 4, price: 1000000),
      ];
      return _json(salons, headers: {'x-total-count': '2'});
    }
    if (path == 'beauty/salons/$_lunaId') {
      return _json({
        'salon': _salon(_lunaId, 'LUNA Beauty Studio',
            rating: 4.8, reviews: 5, discount: promoPercent),
        'description': 'Салон красоты (демо).',
        'phone': '+77000000900',
        'cancellationPolicy': 'Бесплатная отмена до начала процедуры.',
        'gallery': <String>[],
        'services': [_service],
        'masters': [_master],
        'reviews': [
          {
            'id': 'r1',
            'authorName': 'Клиент',
            'rating': 5,
            'comment': 'Отлично'
          }
        ],
      });
    }
    if (path == 'beauty/services/$_serviceId') {
      return _json({
        'service': _service,
        'includes': ['Консультация колориста', 'Окрашивание'],
        'preparation': 'Не мойте голову за день.',
        'cancellationPolicy': 'Бесплатная отмена до начала процедуры.',
        'gallery': <String>[],
        'salon': _salon(_lunaId, 'LUNA Beauty Studio',
            rating: 4.8, reviews: 5, discount: promoPercent),
        'masters': [_master],
      });
    }
    if (path == 'booking/slots') {
      final date = request.url.queryParameters['date']!;
      return _json([
        for (final t in ['10:00', '11:00', '14:00'])
          {
            'startsAt': '${date}T$t:00+05:00',
            'masterId': _masterId,
            'masterName': 'Алия С.',
          }
      ]);
    }
    if (path == 'booking/bookings' && request.method == 'POST') {
      booked = jsonDecode(request.body) as Map<String, dynamic>;
      final starts = booked!['startsAt'] as String;
      final expected = booked!['expectedPriceMinor'] as int;
      return _json({
        'id': 'cccccccc-0000-0000-0000-000000000001',
        'venueId': _lunaId,
        'venueName': 'LUNA Beauty Studio',
        'venueAddress': 'Алматы, ул. Сатпаева, 90',
        'serviceName': 'Окрашивание волос',
        'durationMinutes': 180,
        'masterId': _masterId,
        'masterName': 'Алия С.',
        'startsAt': starts,
        'endsAt': '${starts.substring(0, 11)}17:00:00+05:00',
        'priceMinor': expected,
        'currency': 'KZT',
        'status': 'CONFIRMED',
        'confirmation': 'DEV_MOCK',
        'cancellable': true,
        'category': 'BARBER',
        'bookingNumber': 'KND-772431',
        if (promoPercent != null) 'discountPercent': promoPercent,
        if (promoPercent != null) 'originalPriceMinor': 2500000,
      }, status: 201);
    }
    if (path == 'booking/bookings') return _json(<Object>[]);
    return http.Response('not found', 404);
  }
}

Future<BookingServices> _services(_Backend backend) async {
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

Future<void> _show(WidgetTester tester, BookingServices services,
    {String language = 'ru', double width = 1080}) async {
  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: KundeLocalizations.localizationsDelegates,
    supportedLocales: KundeLocalizations.supportedLocales,
    locale: Locale(language),
    home: BeautyScope(child: BeautyShell(services: services)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  test('money, duration and dates are formatted for each language', () {
    const ru = KundeLocalizations(Locale('ru'));
    const kk = KundeLocalizations(Locale('kk'));
    const en = KundeLocalizations(Locale('en'));
    expect(ru.bMoney(2500000), '25\u00A0000\u00A0₸');
    expect(en.bMoney(2500000), '₸25,000');
    expect(ru.bMoney(1250050), '12\u00A0500,50\u00A0₸');
    expect(ru.bDuration(180), '3 ч');
    expect(ru.bDuration(95), '1 ч 35 мин');
    expect(en.bDuration(95), '1 h 35 min');
    final day = DateTime(2026, 11, 20, 14);
    expect(ru.bDayTime(day), '20 ноября, 14:00');
    expect(kk.bDayTime(day), '20 қараша, 14:00');
    expect(en.bDayTime(day), 'Nov 20, 14:00');
    expect(ru.bMonthYear(day), 'Ноябрь 2026');
    expect(ru.bReviewsCount(1), '1 отзыв');
    expect(ru.bReviewsCount(3), '3 отзыва');
    expect(ru.bReviewsCount(11), '11 отзывов');
    expect(ru.bFromPrice(500000), 'от 5\u00A0000\u00A0₸');
  });

  testWidgets(
      'home shows the categories from the server and the real promotion banner',
      (tester) async {
    final services = await _services(_Backend(promoPercent: 30));
    await _show(tester, services);

    expect(find.text('Красота и уход'), findsOneWidget);
    expect(find.text('Салоны, мастера и уходовые услуги'), findsOneWidget);
    expect(find.text('Алматы'), findsOneWidget);
    expect(find.text('Салоны'), findsOneWidget);
    expect(find.text('Волосы'), findsOneWidget);
    expect(find.text('Ещё'), findsOneWidget);
    expect(find.textContaining('до 30%'), findsOneWidget);
    expect(find.text('Главная'), findsOneWidget);
    expect(find.text('Каталог'), findsOneWidget);
    expect(find.text('Акции'), findsOneWidget);
    expect(find.text('Профиль'), findsOneWidget);
  });

  testWidgets('no banner and no invented discount without a real promotion',
      (tester) async {
    final services = await _services(_Backend());
    await _show(tester, services);

    expect(find.textContaining('до '), findsNothing);
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('home renders in Kazakh and English', (tester) async {
    final services = await _services(_Backend());
    await _show(tester, services, language: 'kk');
    expect(find.text('Сұлулық және күтім'), findsOneWidget);
    expect(find.text('Басты'), findsOneWidget);
    await _show(tester, services, language: 'en');
    expect(find.text('Beauty & Care'), findsOneWidget);
    expect(find.text('Offers'), findsOneWidget);
  });

  testWidgets('a category opens the catalog with a server-side filter',
      (tester) async {
    final backend = _Backend(promoPercent: 30);
    final services = await _services(backend);
    // Wide enough for the four filter chips (test font glyphs are as wide as they are tall).
    await _show(tester, services, width: 1500);

    await tester.tap(find.text('Волосы'));
    await tester.pumpAndSettle();

    expect(find.text('Салоны красоты'), findsOneWidget);
    expect(find.text('Найдено: 2'), findsOneWidget);
    expect(find.text('LUNA Beauty Studio'), findsOneWidget);
    expect(find.text('Aura Beauty'), findsOneWidget);
    expect(backend.lastSalonQuery!['category'], 'HAIR');
    expect(backend.lastSalonQuery!['filter'], 'ALL');

    await tester.tap(find.widgetWithText(BeautyFilterChip, 'Рейтинг'));
    await tester.pumpAndSettle();
    expect(backend.lastSalonQuery!['filter'], 'RATING');
    final promo = find.widgetWithText(BeautyFilterChip, 'Акции');
    await tester.tap(promo);
    await tester.pumpAndSettle();
    expect(backend.lastSalonQuery!['filter'], 'PROMO');
  });

  testWidgets('a customer books a service and sees the confirmed booking',
      (tester) async {
    final backend = _Backend(promoPercent: 30);
    final services = await _services(backend);
    await _show(tester, services);

    await tester.tap(find.text('Салоны'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('LUNA Beauty Studio'));
    await tester.pumpAndSettle();
    expect(find.text('Услуги'), findsOneWidget);
    await tester.tap(find.text('Окрашивание волос'));
    await tester.pumpAndSettle();

    expect(find.text('от 25\u00A0000\u00A0₸'), findsWidgets);
    expect(find.text('3 ч'), findsOneWidget);
    expect(find.text('Волосы'), findsOneWidget);
    await tester.tap(find.text('Записаться'));
    await tester.pumpAndSettle();

    expect(find.text('Выберите мастера'), findsOneWidget);
    expect(find.text('Любой мастер'), findsOneWidget);
    await tester.tap(find.text('Алия С.'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();

    expect(find.text('Выбор даты и времени'), findsOneWidget);
    expect(find.text('Доступное время'), findsOneWidget);
    await tester.tap(find.text('14:00'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();

    expect(find.text('Оформление записи'), findsOneWidget);
    expect(find.text('Скидка 30%'), findsOneWidget);
    expect(find.text('17\u00A0500\u00A0₸'), findsOneWidget);
    await tester.tap(find.text('Записаться · 17\u00A0500\u00A0₸'));
    await tester.pumpAndSettle();

    expect(find.text('Запись подтверждена!'), findsOneWidget);
    expect(find.text('№KND-772431'), findsOneWidget);
    expect(find.text('Добавить в календарь'), findsOneWidget);
    expect(find.text('Построить маршрут'), findsOneWidget);
    expect(backend.booked!['expectedPriceMinor'], 1750000);
    expect(backend.booked!['masterId'], _masterId);
    expect(backend.booked!['idempotencyKey'], isNull);

    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();
    expect(find.text('Мои записи'), findsOneWidget);
  });

  test('salon query copies keep unrelated filters', () {
    const query = BeautySalonQuery(category: 'HAIR', verifiedOnly: true);
    final next = query.copyWith(filter: BeautyFilter.rating);
    expect(next.category, 'HAIR');
    expect(next.verifiedOnly, isTrue);
    expect(next.filter, BeautyFilter.rating);
    expect(query.hasExtraFilters, isTrue);
    expect(const BeautySalonQuery().hasExtraFilters, isFalse);
    expect(next.copyWith(clearCategory: true).category, isNull);
  });
}
