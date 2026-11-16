/// Models of the KUNDE booking API (`/api/v1/booking`): barbershops, services, masters, slots and bookings.
library;

export '../../food/data/food_models.dart' show formatTenge;

/// `45 мин`, `1 ч`, `1 ч 15 мин`.
String formatDuration(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '$m мин';
  return m == 0 ? '$h ч' : '$h ч $m мин';
}

const _weekdays = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];
const _months = [
  'января',
  'февраля',
  'марта',
  'апреля',
  'мая',
  'июня',
  'июля',
  'августа',
  'сентября',
  'октября',
  'ноября',
  'декабря'
];

String _two(int v) => v.toString().padLeft(2, '0');

/// `14:30` in the venue's local time. The API sends offsets (+05:00); the app shows the wall-clock time of that offset.
String formatClock(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

/// `Сб, 22 ноября`.
String formatDay(DateTime t) =>
    '${_weekdays[t.weekday - 1]}, ${t.day} ${_months[t.month - 1]}';

/// Parses an ISO timestamp with offset and keeps the venue wall-clock fields (no conversion to the phone's zone).
DateTime parseVenueTime(String iso) {
  final match =
      RegExp(r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})').firstMatch(iso);
  if (match == null) throw FormatException('Invalid timestamp: $iso');
  return DateTime(int.parse(match[1]!), int.parse(match[2]!),
      int.parse(match[3]!), int.parse(match[4]!), int.parse(match[5]!));
}

class BookingVenue {
  const BookingVenue({
    required this.id,
    required this.name,
    required this.description,
    required this.addressText,
    required this.emoji,
    required this.tone,
    required this.open,
    required this.synthetic,
    this.category = 'BARBER',
    this.fromPriceMinor,
    this.imageUrl,
  });

  final String id;
  final String name;
  final String description;
  final String addressText;
  final String emoji;
  final String tone;
  final bool open;
  final bool synthetic;
  final String category;
  final int? fromPriceMinor;
  final String? imageUrl;

  factory BookingVenue.fromJson(Map<String, dynamic> json) => BookingVenue(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        addressText: json['addressText'] as String,
        emoji: json['emoji'] as String? ?? '💈',
        tone: json['tone'] as String? ?? 'blue',
        open: json['open'] as bool? ?? false,
        synthetic: json['synthetic'] as bool? ?? false,
        category: json['category'] as String? ?? 'BARBER',
        fromPriceMinor: (json['fromPriceMinor'] as num?)?.toInt(),
        imageUrl: json['imageUrl'] as String?,
      );
}

class BookableService {
  const BookableService({
    required this.id,
    required this.name,
    required this.description,
    required this.durationMinutes,
    required this.priceMinor,
    required this.available,
    this.pricePerSqmMinor = 0,
    this.minAreaSqm,
    this.maxAreaSqm,
  });

  final String id;
  final String name;
  final String description;
  final int durationMinutes;
  final int priceMinor;
  final bool available;

  /// Area-based pricing (home services): `priceMinor` + `pricePerSqmMinor` x area, area within [minAreaSqm, maxAreaSqm].
  final int pricePerSqmMinor;
  final int? minAreaSqm;
  final int? maxAreaSqm;

  bool get areaBased => pricePerSqmMinor > 0 && minAreaSqm != null;

  /// Same formula as the server (which is the authority); `null` when the area is missing or out of range.
  int? priceFor(int? areaSqm) {
    if (!areaBased) return priceMinor;
    if (areaSqm == null || areaSqm < minAreaSqm! || areaSqm > maxAreaSqm!) {
      return null;
    }
    return priceMinor + pricePerSqmMinor * areaSqm;
  }

  factory BookableService.fromJson(Map<String, dynamic> json) =>
      BookableService(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        durationMinutes: (json['durationMinutes'] as num).toInt(),
        priceMinor: (json['priceMinor'] as num).toInt(),
        available: json['available'] as bool? ?? false,
        pricePerSqmMinor: (json['pricePerSqmMinor'] as num?)?.toInt() ?? 0,
        minAreaSqm: (json['minAreaSqm'] as num?)?.toInt(),
        maxAreaSqm: (json['maxAreaSqm'] as num?)?.toInt(),
      );
}

class BookingMaster {
  const BookingMaster({
    required this.id,
    required this.name,
    required this.bio,
    required this.emoji,
    required this.tone,
    required this.serviceIds,
  });

  final String id;
  final String name;
  final String bio;
  final String emoji;
  final String tone;
  final List<String> serviceIds;

  factory BookingMaster.fromJson(Map<String, dynamic> json) => BookingMaster(
        id: json['id'] as String,
        name: json['name'] as String,
        bio: json['bio'] as String? ?? '',
        emoji: json['emoji'] as String? ?? '💇',
        tone: json['tone'] as String? ?? 'amber',
        serviceIds:
            (json['serviceIds'] as List<dynamic>? ?? const []).cast<String>(),
      );
}

class VenueDetail {
  const VenueDetail(
      {required this.venue, required this.services, required this.masters});

  final BookingVenue venue;
  final List<BookableService> services;
  final List<BookingMaster> masters;

  List<BookingMaster> mastersFor(String serviceId) => masters
      .where((m) => m.serviceIds.contains(serviceId))
      .toList(growable: false);

  factory VenueDetail.fromJson(Map<String, dynamic> json) => VenueDetail(
        venue: BookingVenue.fromJson(json['venue'] as Map<String, dynamic>),
        services: (json['services'] as List<dynamic>)
            .map((e) => BookableService.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        masters: (json['masters'] as List<dynamic>)
            .map((e) => BookingMaster.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );
}

class BookingSlot {
  const BookingSlot(
      {required this.startsAtIso,
      required this.start,
      required this.masterId,
      required this.masterName});

  /// The exact value the API sent; it is sent back unchanged when booking.
  final String startsAtIso;
  final DateTime start;
  final String masterId;
  final String masterName;

  factory BookingSlot.fromJson(Map<String, dynamic> json) => BookingSlot(
        startsAtIso: json['startsAt'] as String,
        start: parseVenueTime(json['startsAt'] as String),
        masterId: json['masterId'] as String,
        masterName: json['masterName'] as String,
      );
}

String bookingStatusLabel(String status) => switch (status) {
      'PENDING' => 'Ожидает подтверждения',
      'CONFIRMED' => 'Подтверждена',
      'COMPLETED' => 'Состоялась',
      'CANCELLED' => 'Отменена',
      _ => status,
    };

class BookingRecord {
  const BookingRecord({
    required this.id,
    required this.venueName,
    required this.venueAddress,
    required this.serviceName,
    required this.durationMinutes,
    required this.masterName,
    required this.startsAtIso,
    required this.start,
    required this.end,
    required this.priceMinor,
    required this.status,
    required this.comment,
    required this.cancellable,
    this.category = 'BARBER',
    this.addressText,
    this.areaSqm,
    this.cancelledBy,
    this.cancelReason,
  });

  final String id;
  final String venueName;
  final String venueAddress;
  final String serviceName;
  final int durationMinutes;
  final String masterName;
  final String startsAtIso;
  final DateTime start;
  final DateTime end;
  final int priceMinor;
  final String status;
  final String? comment;
  final bool cancellable;

  /// `BARBER` (Beauty) or `CLEANING` (Home services); older records default to `BARBER`.
  final String category;
  final String? addressText;
  final int? areaSqm;

  /// Who cancelled (`CUSTOMER`, `PARTNER`, `SYSTEM`) and the partner's reason, if any.
  final String? cancelledBy;
  final String? cancelReason;

  bool get isCleaning => category == 'CLEANING';

  factory BookingRecord.fromJson(Map<String, dynamic> json) => BookingRecord(
        id: json['id'] as String,
        venueName: json['venueName'] as String,
        venueAddress: json['venueAddress'] as String,
        serviceName: json['serviceName'] as String,
        durationMinutes: (json['durationMinutes'] as num).toInt(),
        masterName: json['masterName'] as String,
        startsAtIso: json['startsAt'] as String,
        start: parseVenueTime(json['startsAt'] as String),
        end: parseVenueTime(json['endsAt'] as String),
        priceMinor: (json['priceMinor'] as num).toInt(),
        status: json['status'] as String,
        comment: json['comment'] as String?,
        cancellable: json['cancellable'] as bool? ?? false,
        category: json['category'] as String? ?? 'BARBER',
        addressText: json['addressText'] as String?,
        areaSqm: (json['areaSqm'] as num?)?.toInt(),
        cancelledBy: json['cancelledBy'] as String?,
        cancelReason: json['cancelReason'] as String?,
      );
}
