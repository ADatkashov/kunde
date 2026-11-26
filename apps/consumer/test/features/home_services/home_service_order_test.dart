import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_api/booking_api.dart';
import 'package:kunde_api/home_services_api.dart';
import 'package:kunde_auth/auth_repository.dart';
import 'package:kunde_mobile/features/booking/booking_services.dart';
import 'package:kunde_mobile/features/home_services/presentation/home_service_order_screen.dart';

const _startsAt = '2026-11-27T18:00:00+05:00';

class _Auth implements AuthRepository {
  final posts = <Map<String, dynamic>>[];
  bool priceChanged = false;
  bool slotTaken = false;

  @override
  Future<dynamic> authorizedJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Set<int> expected = const {200},
    Map<String, String>? headers,
  }) async {
    if (method == 'POST' && path == 'booking/bookings') {
      posts.add(body!);
      if (slotTaken) {
        throw IdentityApiError(409, 'SLOT_TAKEN');
      }
      if (priceChanged) {
        throw IdentityApiError(409, 'BOOKING_PRICE_CHANGED');
      }
      return {
        'id': 'b1',
        'venueName': 'Clean Co',
        'venueAddress': 'Abay 1',
        'serviceName': 'Deep cleaning',
        'durationMinutes': 180,
        'masterName': 'Мастер',
        'startsAt': _startsAt,
        'endsAt': '2026-11-27T21:00:00+05:00',
        'priceMinor': body['expectedPriceMinor'],
        'status': 'PENDING',
        'category': 'CLEANING',
      };
    }
    return {};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Catalog implements HomeServicesCatalog {
  final startsAtSeen = <String?>[];
  final urgentSeen = <bool>[];
  final areaSeen = <int?>[];

  @override
  Future<List<HomeServiceOffer>> offers(
          {String? category, int limit = 20, int offset = 0}) async =>
      const [];

  @override
  Future<HomeServiceQuote> quote(String offerId,
      {int? areaSqm,
      String? startsAtIso,
      double? lat,
      double? lng,
      bool urgent = false}) async {
    startsAtSeen.add(startsAtIso);
    urgentSeen.add(urgent);
    areaSeen.add(areaSqm);
    return HomeServiceQuote(
      listPriceMinor: 1500000,
      callOutFeeMinor: 0,
      urgentSurchargeMinor: urgent ? 300000 : 0,
      eveningSurchargeMinor: 0,
      totalMinor: 1500000 + (urgent ? 300000 : 0),
      currency: 'KZT',
    );
  }
}

http.Response _slots(http.Request r) => http.Response(
    jsonEncode([
      {'startsAt': _startsAt, 'masterId': 'm1', 'masterName': 'Мастер'},
      {'startsAt': _startsAt, 'masterId': 'm2', 'masterName': 'Мастер 2'},
    ]),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'});

class _Services implements BookingServices {
  _Services(this.auth)
      : api = BookingApi(
            baseUri: Uri.parse('https://api.example.test/api/v1/'),
            auth: auth,
            client: MockClient((r) async => _slots(r)));

  @override
  final BookingApi api;
  @override
  final AuthRepository auth;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

HomeServiceOffer _offerWith([int perSqm = 0]) => HomeServiceOffer.fromJson({
      'pricePerSqmMinor': perSqm,
      'id': 'o1',
      'serviceId': 's1',
      'venueId': 'v1',
      'venueName': 'Clean Co',
      'definitionCode': 'DEEP_CLEAN',
      'categoryCode': 'CLEANING',
      'nameRu': 'Генеральная уборка',
      'nameKk': 'Күрделі жинау',
      'nameEn': 'Deep cleaning',
      'priceMinor': 1500000,
      'pricingModel': 'FROM',
      'durationMinutes': 180,
      'homeVisit': true,
      'warrantyDays': 14,
    });

Future<void> _open(WidgetTester tester, _Auth auth, _Catalog catalog,
    [int perSqm = 0, int? area, bool urgent = false]) async {
  tester.view.physicalSize = const Size(1080, 2600);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('en'),
    supportedLocales: const [Locale('en')],
    home: HomeServiceOrderScreen(
        offer: _offerWith(perSqm),
        services: _Services(auth),
        api: catalog,
        initialAreaSqm: area,
        initialUrgent: urgent),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('area and urgency chosen on the offer card carry into the order',
      (tester) async {
    final catalog = _Catalog();
    await _open(tester, _Auth(), catalog, 450000, 50, true);
    await tester.tap(find.byKey(const ValueKey('slot-$_startsAt')));
    await tester.pumpAndSettle();
    expect(catalog.areaSeen, [50]);
    expect(catalog.urgentSeen, [true]);
    expect(find.text('18\u00A0000\u00A0₸'), findsWidgets);
  });

  testWidgets('a taken slot is explained even though the price is gone',
      (tester) async {
    final auth = _Auth()..slotTaken = true;
    await _open(tester, auth, _Catalog());
    await tester.tap(find.byKey(const ValueKey('slot-$_startsAt')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('address')), 'Abay 150');
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('submit')));
    await tester.tap(find.byKey(const ValueKey('submit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('That time was just taken'), findsOneWidget);
    expect(find.byKey(const ValueKey('submit')), findsNothing);
  });

  testWidgets('an area-priced service asks for the area before ordering',
      (tester) async {
    final auth = _Auth();
    await _open(tester, auth, _Catalog(), 450000);
    await tester.tap(find.byKey(const ValueKey('slot-$_startsAt')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('address')), 'Abay 150');
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('submit')));
    await tester.tap(find.byKey(const ValueKey('submit')));
    await tester.pumpAndSettle();
    expect(find.text('Enter the area'), findsOneWidget);
    expect(auth.posts, isEmpty);
    await tester.enterText(find.byKey(const ValueKey('area')), '50');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('submit')));
    await tester.tap(find.byKey(const ValueKey('submit')));
    await tester.pumpAndSettle();
    expect(auth.posts.single['areaSqm'], 50);
  });

  testWidgets(
      'order sends the quoted total and urgency; one chip per start time',
      (tester) async {
    final auth = _Auth();
    final catalog = _Catalog();
    await _open(tester, auth, catalog);
    expect(find.byKey(const ValueKey('slot-$_startsAt')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('slot-$_startsAt')));
    await tester.pumpAndSettle();
    expect(catalog.startsAtSeen, [_startsAt]);
    await tester.tap(find.byKey(const ValueKey('urgent')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('address')), 'Abay 150');
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('submit')));
    expect(find.textContaining('Order for 18'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('submit')));
    await tester.pumpAndSettle();
    expect(auth.posts, hasLength(1));
    expect(auth.posts.single['expectedPriceMinor'], 1800000);
    expect(auth.posts.single['urgent'], true);
    expect(auth.posts.single['masterId'], 'm1');
    expect(auth.posts.single['addressText'], 'Abay 150');
  });

  testWidgets('a changed price is explained and re-quoted, not charged',
      (tester) async {
    final auth = _Auth()..priceChanged = true;
    final catalog = _Catalog();
    await _open(tester, auth, catalog);
    await tester.tap(find.byKey(const ValueKey('slot-$_startsAt')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('address')), 'Abay 150');
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('submit')));
    await tester.tap(find.byKey(const ValueKey('submit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('The price changed'), findsOneWidget);
    expect(catalog.startsAtSeen, hasLength(2));
  });
}
