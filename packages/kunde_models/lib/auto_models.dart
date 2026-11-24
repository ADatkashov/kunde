/// Models of the KUNDE Auto API (`/api/v1/auto`): categories, venues, services, slots, vehicles, quotes and bookings.
library;

import 'package:kunde_models/booking_models.dart' show parseVenueTime;

export 'package:kunde_models/booking_models.dart'
    show formatClock, formatDay, formatDuration, formatTenge, parseVenueTime;

String _str(Map<String, dynamic> j, String k) {
  final v = j[k];
  if (v is! String) throw FormatException('Missing $k');
  return v;
}

int _int(Map<String, dynamic> j, String k) {
  final v = j[k];
  if (v is! int) throw FormatException('Missing $k');
  return v;
}

class AutoCategory {
  const AutoCategory(
      {required this.code,
      required this.nameRu,
      required this.nameKk,
      required this.nameEn,
      required this.mobile,
      required this.enabled});

  final String code;
  final String nameRu;
  final String nameKk;
  final String nameEn;
  final bool mobile;
  final bool enabled;

  String name(String languageCode) => switch (languageCode) {
        'kk' => nameKk,
        'en' => nameEn,
        _ => nameRu,
      };

  factory AutoCategory.fromJson(Map<String, dynamic> j) => AutoCategory(
      code: _str(j, 'code'),
      nameRu: _str(j, 'nameRu'),
      nameKk: _str(j, 'nameKk'),
      nameEn: _str(j, 'nameEn'),
      mobile: j['mobile'] == true,
      enabled: j['enabled'] == true);
}

class AutoVenue {
  const AutoVenue(
      {required this.id,
      required this.name,
      required this.description,
      required this.addressText,
      required this.open,
      required this.synthetic,
      required this.categories,
      this.rating,
      this.reviews = 0,
      this.fromPriceMinor});

  final String id;
  final String name;
  final String description;
  final String addressText;
  final bool open;
  final bool synthetic;
  final int? fromPriceMinor;
  final List<String> categories;
  final double? rating;
  final int reviews;

  factory AutoVenue.fromJson(Map<String, dynamic> j) => AutoVenue(
          id: _str(j, 'id'),
          name: _str(j, 'name'),
          description: _str(j, 'description'),
          addressText: _str(j, 'addressText'),
          open: j['open'] == true,
          synthetic: j['synthetic'] == true,
          fromPriceMinor: j['fromPriceMinor'] as int?,
          rating: (j['rating'] as num?)?.toDouble(),
          reviews: j['reviews'] as int? ?? 0,
          categories: [
            for (final c in (j['categories'] as List<dynamic>? ?? const []))
              c as String
          ]);
}

/// `FIXED` final price, `FROM` price from (agreed after inspection), `DIAGNOSTIC` follow-up work agreed separately.
class AutoService {
  const AutoService(
      {required this.id,
      required this.name,
      required this.description,
      required this.category,
      required this.durationMinutes,
      required this.priceMinor,
      required this.priceKind,
      required this.conditions,
      required this.available});

  final String id;
  final String name;
  final String description;
  final String category;
  final int durationMinutes;
  final int priceMinor;
  final String priceKind;
  final String conditions;
  final bool available;

  factory AutoService.fromJson(Map<String, dynamic> j) => AutoService(
      id: _str(j, 'id'),
      name: _str(j, 'name'),
      description: _str(j, 'description'),
      category: _str(j, 'category'),
      durationMinutes: _int(j, 'durationMinutes'),
      priceMinor: _int(j, 'priceMinor'),
      priceKind: _str(j, 'priceKind'),
      conditions: j['conditions'] as String? ?? '',
      available: j['available'] == true);
}

class AutoVenueDetail {
  const AutoVenueDetail(
      {required this.venue,
      required this.services,
      required this.cancellationTerms});

  final AutoVenue venue;
  final List<AutoService> services;
  final String cancellationTerms;

  factory AutoVenueDetail.fromJson(Map<String, dynamic> j) => AutoVenueDetail(
      venue: AutoVenue.fromJson(j['venue'] as Map<String, dynamic>),
      services: [
        for (final s in (j['services'] as List<dynamic>))
          AutoService.fromJson(s as Map<String, dynamic>)
      ],
      cancellationTerms: j['cancellationTerms'] as String? ?? '');
}

class AutoSlot {
  const AutoSlot({required this.startsAtIso});

  final String startsAtIso;
  DateTime get time => parseVenueTime(startsAtIso);

  factory AutoSlot.fromJson(Map<String, dynamic> j) =>
      AutoSlot(startsAtIso: _str(j, 'startsAt'));
}

class Vehicle {
  const Vehicle(
      {required this.id,
      required this.make,
      required this.model,
      required this.year,
      required this.version,
      this.plate});

  final String id;
  final String make;
  final String model;
  final int year;
  final String? plate;
  final int version;

  String get label => '$make $model $year${plate == null ? '' : ' $plate'}';

  factory Vehicle.fromJson(Map<String, dynamic> j) => Vehicle(
      id: _str(j, 'id'),
      make: _str(j, 'make'),
      model: _str(j, 'model'),
      year: _int(j, 'year'),
      plate: j['plate'] as String?,
      version: _int(j, 'version'));
}

class AutoQuote {
  const AutoQuote(
      {required this.id,
      required this.startsAtIso,
      required this.durationMinutes,
      required this.priceMinor,
      required this.priceKind,
      required this.expiresAt,
      required this.cancellationTerms});

  final String id;
  final String startsAtIso;
  final int durationMinutes;
  final int priceMinor;
  final String priceKind;
  final DateTime expiresAt;
  final String cancellationTerms;

  factory AutoQuote.fromJson(Map<String, dynamic> j) => AutoQuote(
      id: _str(j, 'id'),
      startsAtIso: _str(j, 'startsAt'),
      durationMinutes: _int(j, 'durationMinutes'),
      priceMinor: _int(j, 'priceMinor'),
      priceKind: _str(j, 'priceKind'),
      expiresAt: DateTime.parse(_str(j, 'expiresAt')),
      cancellationTerms: j['cancellationTerms'] as String? ?? '');
}

class AutoTimelineEntry {
  const AutoTimelineEntry({required this.status, this.reason});

  final String status;
  final String? reason;

  factory AutoTimelineEntry.fromJson(Map<String, dynamic> j) =>
      AutoTimelineEntry(
          status: _str(j, 'status'), reason: j['reason'] as String?);
}

class AutoBookingRecord {
  const AutoBookingRecord(
      {required this.id,
      required this.venueId,
      required this.venueName,
      required this.venueAddress,
      required this.serviceName,
      required this.durationMinutes,
      required this.vehicle,
      required this.startsAtIso,
      required this.priceMinor,
      required this.priceKind,
      required this.status,
      required this.cancellable,
      required this.reschedulable,
      required this.timeline,
      required this.serviceId,
      this.finalPriceMinor,
      this.priceApproval,
      this.payment,
      this.cancelReason});

  final String id;
  final String venueId;
  final String venueName;
  final String venueAddress;
  final String serviceName;
  final int durationMinutes;
  final String vehicle;
  final String startsAtIso;
  final int priceMinor;
  final String priceKind;
  final int? finalPriceMinor;
  final String? priceApproval;
  final AutoPayment? payment;
  final String status;
  final bool cancellable;
  final bool reschedulable;
  final String? cancelReason;
  final List<AutoTimelineEntry> timeline;
  final String serviceId;

  DateTime get startsAt => parseVenueTime(startsAtIso);

  bool get active => const {'PENDING', 'CONFIRMED', 'CHECKED_IN', 'IN_PROGRESS'}
      .contains(status);

  bool get awaitsPriceDecision => priceApproval == 'PENDING';

  factory AutoBookingRecord.fromJson(Map<String, dynamic> j) =>
      AutoBookingRecord(
          id: _str(j, 'id'),
          venueId: _str(j, 'venueId'),
          venueName: _str(j, 'venueName'),
          venueAddress: _str(j, 'venueAddress'),
          serviceName: _str(j, 'serviceName'),
          durationMinutes: _int(j, 'durationMinutes'),
          vehicle: _str(j, 'vehicle'),
          startsAtIso: _str(j, 'startsAt'),
          priceMinor: _int(j, 'priceMinor'),
          priceKind: _str(j, 'priceKind'),
          finalPriceMinor: j['finalPriceMinor'] as int?,
          priceApproval: j['priceApproval'] as String?,
          payment: j['payment'] is Map<String, dynamic>
              ? AutoPayment.fromJson(j['payment'] as Map<String, dynamic>)
              : null,
          status: _str(j, 'status'),
          cancellable: j['cancellable'] == true,
          reschedulable: j['reschedulable'] == true,
          cancelReason: j['cancelReason'] as String?,
          serviceId: j['serviceId'] as String? ?? '',
          timeline: [
            for (final t in (j['timeline'] as List<dynamic>? ?? const []))
              AutoTimelineEntry.fromJson(t as Map<String, dynamic>)
          ]);
}

/// DEV/TEST payment record of a booking: a ledger entry only, nothing is ever charged.
class AutoPayment {
  const AutoPayment(
      {required this.method,
      required this.status,
      required this.heldMinor,
      required this.capturedMinor,
      required this.refundedMinor});

  final String method;
  final String status;
  final int heldMinor;
  final int capturedMinor;
  final int refundedMinor;

  bool get isTest => method == 'TEST_CARD';

  factory AutoPayment.fromJson(Map<String, dynamic> j) => AutoPayment(
      method: j['method'] as String? ?? 'PAY_ON_SITE',
      status: j['status'] as String? ?? '',
      heldMinor: (j['heldMinor'] as num?)?.toInt() ?? 0,
      capturedMinor: (j['capturedMinor'] as num?)?.toInt() ?? 0,
      refundedMinor: (j['refundedMinor'] as num?)?.toInt() ?? 0);
}
