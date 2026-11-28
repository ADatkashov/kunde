import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_api/booking_api.dart';
import 'package:kunde_api/home_services_api.dart';
import 'package:kunde_auth/auth_repository.dart';
import 'package:kunde_design/kunde_theme.dart';
import 'package:kunde_localization/kunde_localizations.dart';
import 'package:kunde_mobile/features/booking/booking_services.dart';
import 'package:kunde_mobile/features/home_services/presentation/home_service_order_screen.dart';
import 'package:kunde_mobile/features/home_services/presentation/home_service_visit_card.dart';
import 'package:kunde_mobile/features/home_services/presentation/home_services_offers_screen.dart';

import '../../support/premium_goldens.dart';

const _startsAt = '2026-11-27T16:00:00+05:00';

HomeServiceOffer _offer(String id, String code, String ru, int price,
        {String model = 'FROM', int perSqm = 0, int warranty = 12}) =>
    HomeServiceOffer.fromJson({
      'id': id,
      'serviceId': 's$id',
      'venueId': 'v1',
      'venueName': 'Мастер Сервис',
      'definitionCode': code,
      'categoryCode': code,
      'nameRu': ru,
      'nameKk': ru,
      'nameEn': ru,
      'priceMinor': price,
      'pricingModel': model,
      'durationMinutes': 90,
      'homeVisit': true,
      'warrantyDays': warranty,
      'pricePerSqmMinor': perSqm,
    });

class _Catalog implements HomeServicesCatalog {
  @override
  Future<List<HomeServiceOffer>> offers(
          {String? category, int limit = 20, int offset = 0}) async =>
      [
        _offer('1', 'CLEANING', 'Генеральная уборка', 1500000,
            perSqm: 45000, warranty: 14),
        _offer('2', 'PLUMBING', 'Сантехник', 800000),
        _offer('3', 'ELECTRICAL', 'Электрик', 700000, warranty: 6),
        _offer('4', 'FURNITURE', 'Сборка мебели', 500000, warranty: 0),
      ];

  @override
  Future<HomeServiceQuote> quote(String offerId,
          {int? areaSqm,
          String? startsAtIso,
          double? lat,
          double? lng,
          bool urgent = false}) async =>
      const HomeServiceQuote(
          listPriceMinor: 800000,
          callOutFeeMinor: 0,
          urgentSurchargeMinor: 0,
          eveningSurchargeMinor: 0,
          totalMinor: 800000,
          currency: 'KZT');
}

class _Auth implements AuthRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Services implements BookingServices {
  _Services()
      : api = BookingApi(
            baseUri: Uri.parse('https://api.example.test/api/v1/'),
            auth: _Auth(),
            client: MockClient((r) async => http.Response(
                jsonEncode([
                  {
                    'startsAt': _startsAt,
                    'masterId': 'm1',
                    'masterName': 'Нурбек'
                  },
                  {
                    'startsAt': '2026-11-27T17:00:00+05:00',
                    'masterId': 'm1',
                    'masterName': 'Нурбек'
                  },
                ]),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'})));

  @override
  final BookingApi api;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _show(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(1080, 2200);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: KundeTheme.light,
      locale: const Locale('ru'),
      supportedLocales: KundeLocalizations.supportedLocales,
      localizationsDelegates: KundeLocalizations.localizationsDelegates,
      home: home));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('premium golden Home Services catalogue, offer and order',
      (tester) async {
    await tester.runAsync(loadPremiumFonts);
    final services = _Services();
    final catalog = _Catalog();
    await _show(
        tester, HomeServicesOffersScreen(services: services, api: catalog));
    await premiumGolden(tester, 'home_services_list');

    final plumbing = (await catalog.offers())[1];
    await _show(
        tester,
        HomeServiceOfferScreen(
            offer: plumbing, services: services, api: catalog));
    await premiumGolden(tester, 'home_services_offer');

    await _show(
        tester,
        HomeServiceOrderScreen(
            offer: plumbing,
            services: services,
            api: catalog,
            today: DateTime(2026, 11, 27)));
    await tester.tap(find.byKey(const ValueKey('slot-$_startsAt')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('address')), 'ул. Абая, 150, кв. 45');
    await tester.pumpAndSettle();
    await premiumGolden(tester, 'home_services_order');

    await _show(
        tester,
        Scaffold(
            body: Padding(
                padding: const EdgeInsets.all(16),
                child: HomeServiceVisitCard(
                    load: () async => {
                          'status': 'CONFIRMED',
                          'stage': 'EN_ROUTE',
                          'etaMinutes': 12
                        }))));
    await premiumGolden(tester, 'home_services_visit');
  });
}
