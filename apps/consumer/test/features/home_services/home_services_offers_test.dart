import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_api/home_services_api.dart';
import 'package:kunde_mobile/features/booking/booking_services.dart';
import 'package:kunde_mobile/features/home_services/presentation/home_services_offers_screen.dart';

class _Fake implements HomeServicesCatalog {
  final quotes = <bool>[];

  @override
  Future<List<HomeServiceOffer>> offers(
          {String? category, int limit = 20, int offset = 0}) async =>
      [
        HomeServiceOffer.fromJson({
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
        }),
      ];

  @override
  Future<HomeServiceQuote> quote(String offerId,
      {int? areaSqm,
      String? startsAtIso,
      double? lat,
      double? lng,
      bool urgent = false}) async {
    quotes.add(urgent);
    return HomeServiceQuote(
      listPriceMinor: 1500000,
      callOutFeeMinor: 50000,
      urgentSurchargeMinor: urgent ? 300000 : 0,
      eveningSurchargeMinor: 0,
      totalMinor: 1550000 + (urgent ? 300000 : 0),
      currency: 'KZT',
    );
  }
}

void main() {
  test('formatKzt groups thousands of tenge from minor units', () {
    expect(formatKzt(1500000), '15 000 ₸');
    expect(formatKzt(800000), '8 000 ₸');
  });

  testWidgets('catalogue card opens an itemised quote that follows urgency',
      (tester) async {
    final api = _Fake();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: const [Locale('en')],
      home: HomeServicesOffersScreen(
        services: _Services(),
        api: api,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Deep cleaning'), findsOneWidget);
    expect(find.text('from 15 000 ₸'), findsOneWidget);

    await tester.tap(find.text('Deep cleaning'));
    await tester.pumpAndSettle();
    expect(find.text('15 500 ₸'), findsWidgets);
    expect(find.text('Urgency'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('urgent')));
    await tester.pumpAndSettle();
    expect(find.text('Urgency'), findsOneWidget);
    expect(find.text('18 500 ₸'), findsOneWidget);
    expect(api.quotes, [false, true]);
  });
}

/// The catalogue screens only forward the services to the booking flow; nothing here touches them.
class _Services implements BookingServices {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
