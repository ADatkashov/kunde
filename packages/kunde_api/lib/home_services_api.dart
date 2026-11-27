import 'dart:convert';

import 'package:kunde_api/booking_api.dart';

/// A published Home Services offer as shown in the public catalogue (`GET /home-services/offers`).
class HomeServiceOffer {
  const HomeServiceOffer({
    required this.id,
    required this.serviceId,
    required this.venueId,
    required this.venueName,
    required this.definitionCode,
    required this.categoryCode,
    required this.nameRu,
    required this.nameKk,
    required this.nameEn,
    required this.priceMinor,
    required this.pricingModel,
    required this.durationMinutes,
    required this.homeVisit,
    required this.warrantyDays,
    this.pricePerSqmMinor = 0,
  });

  factory HomeServiceOffer.fromJson(Map<String, dynamic> json) =>
      HomeServiceOffer(
        id: json['id'] as String,
        serviceId: json['serviceId'] as String,
        venueId: json['venueId'] as String,
        venueName: json['venueName'] as String,
        definitionCode: json['definitionCode'] as String,
        categoryCode: json['categoryCode'] as String,
        nameRu: json['nameRu'] as String,
        nameKk: json['nameKk'] as String,
        nameEn: json['nameEn'] as String,
        priceMinor: (json['priceMinor'] as num).toInt(),
        pricingModel: json['pricingModel'] as String,
        durationMinutes: (json['durationMinutes'] as num).toInt(),
        homeVisit: json['homeVisit'] as bool,
        warrantyDays: (json['warrantyDays'] as num).toInt(),
        pricePerSqmMinor: (json['pricePerSqmMinor'] as num?)?.toInt() ?? 0,
      );

  final String id;
  final String serviceId;
  final String venueId;
  final String venueName;
  final String definitionCode;
  final String categoryCode;
  final String nameRu;
  final String nameKk;
  final String nameEn;
  final int priceMinor;
  final String pricingModel;
  final int durationMinutes;
  final bool homeVisit;
  final int warrantyDays;

  /// Above zero when the service is priced by area: the customer must give the area and the quote depends on it.
  final int pricePerSqmMinor;

  bool get areaBased => pricePerSqmMinor > 0;

  String name(String language) => switch (language) {
        'kk' => nameKk,
        'en' => nameEn,
        _ => nameRu,
      };
}

/// Itemised price of one offer (`GET /home-services/offers/{id}/quote`); amounts are minor units (tiyn).
class HomeServiceQuote {
  const HomeServiceQuote({
    required this.listPriceMinor,
    required this.callOutFeeMinor,
    required this.urgentSurchargeMinor,
    required this.eveningSurchargeMinor,
    required this.totalMinor,
    required this.currency,
  });

  factory HomeServiceQuote.fromJson(Map<String, dynamic> json) =>
      HomeServiceQuote(
        listPriceMinor: (json['listPriceMinor'] as num).toInt(),
        callOutFeeMinor: (json['callOutFeeMinor'] as num).toInt(),
        urgentSurchargeMinor: (json['urgentSurchargeMinor'] as num).toInt(),
        eveningSurchargeMinor: (json['eveningSurchargeMinor'] as num).toInt(),
        totalMinor: (json['totalMinor'] as num).toInt(),
        currency: json['currency'] as String,
      );

  final int listPriceMinor;
  final int callOutFeeMinor;
  final int urgentSurchargeMinor;
  final int eveningSurchargeMinor;
  final int totalMinor;
  final String currency;
}

/// What screens need from the public catalogue; tests substitute a fake.
abstract interface class HomeServicesCatalog {
  Future<List<HomeServiceOffer>> offers(
      {String? category, int limit = 20, int offset = 0});

  Future<HomeServiceQuote> quote(String offerId,
      {int? areaSqm,
      String? startsAtIso,
      double? lat,
      double? lng,
      bool urgent = false});
}

/// Public Home Services catalogue on the booking transport (same error mapping, no auth).
class HomeServicesApi implements HomeServicesCatalog {
  HomeServicesApi(this._booking);

  final BookingApi _booking;

  @override
  Future<List<HomeServiceOffer>> offers(
      {String? category, int limit = 20, int offset = 0}) async {
    final response = await _booking.publicResponse('home-services/offers', {
      if (category != null) 'category': category,
      'limit': '$limit',
      'offset': '$offset',
    });
    return _booking.guarded(() async =>
        (jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>)
            .map((e) => HomeServiceOffer.fromJson(e as Map<String, dynamic>))
            .toList());
  }

  @override
  Future<HomeServiceQuote> quote(String offerId,
      {int? areaSqm,
      String? startsAtIso,
      double? lat,
      double? lng,
      bool urgent = false}) async {
    final response =
        await _booking.publicResponse('home-services/offers/$offerId/quote', {
      if (areaSqm != null) 'areaSqm': '$areaSqm',
      if (startsAtIso != null) 'startsAt': startsAtIso,
      if (lat != null) 'lat': '$lat',
      if (lng != null) 'lng': '$lng',
      if (urgent) 'urgent': 'true',
    });
    return _booking.guarded(() async => HomeServiceQuote.fromJson(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>));
  }
}
