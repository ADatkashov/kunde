export 'package:kunde_models/food_models.dart' show formatTenge;

String _s(Map<String, dynamic> j, String k) {
  final v = j[k];
  if (v is! String) throw FormatException('Missing $k');
  return v;
}

int _i(Map<String, dynamic> j, String k) {
  final v = j[k];
  if (v is! num) throw FormatException('Missing $k');
  return v.toInt();
}

List<String> _strings(Object? v) =>
    v is List ? v.whereType<String>().toList(growable: false) : const [];

/// Keeps the wall-clock of the venue offset (+05:00), like the rest of the app; the phone zone never shifts a session.
DateTime venueTime(String iso) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})').firstMatch(iso);
  if (m == null) throw FormatException('Invalid timestamp: $iso');
  return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!),
      int.parse(m[4]!), int.parse(m[5]!));
}

enum BookingType {
  timeSlot,
  capacity,
  seatMap,
  generalAdmission,
  privateSession;

  static BookingType parse(String v) => switch (v) {
        'TIME_SLOT' => timeSlot,
        'CAPACITY' => capacity,
        'SEAT_MAP' => seatMap,
        'PRIVATE_SESSION' => privateSession,
        _ => generalAdmission,
      };

  /// One price for the whole booking (a lane, a room) instead of a price per person.
  bool get perBooking => this == timeSlot || this == privateSession;
}

class LeisureCategory {
  const LeisureCategory({
    required this.code,
    required this.nameRu,
    required this.nameKk,
    required this.nameEn,
    required this.bookingType,
    required this.familyFriendly,
  });

  final String code;
  final String nameRu;
  final String nameKk;
  final String nameEn;
  final BookingType bookingType;
  final bool familyFriendly;

  String name(String lang) => switch (lang) {
        'kk' => nameKk,
        'en' => nameEn,
        _ => nameRu,
      };

  factory LeisureCategory.fromJson(Map<String, dynamic> j) => LeisureCategory(
        code: _s(j, 'code'),
        nameRu: _s(j, 'nameRu'),
        nameKk: _s(j, 'nameKk'),
        nameEn: _s(j, 'nameEn'),
        bookingType: BookingType.parse(_s(j, 'bookingType')),
        familyFriendly: j['familyFriendly'] == true,
      );
}

class EventCard {
  const EventCard({
    required this.id,
    required this.title,
    required this.venueName,
    required this.district,
    required this.address,
    required this.categoryCode,
    required this.bookingType,
    required this.photoUrl,
    required this.minPriceMinor,
    required this.minAge,
    required this.familyFriendly,
    required this.rating,
    required this.reviewCount,
    required this.nextSessionAt,
    required this.nextSessionId,
    required this.nextSessionFree,
    required this.distanceKm,
  });

  final String id;
  final String title;
  final String venueName;
  final String district;
  final String address;
  final String categoryCode;
  final BookingType bookingType;
  final String? photoUrl;
  final int minPriceMinor;
  final int minAge;
  final bool familyFriendly;

  /// Average of real published reviews; null while there are none (nothing is invented).
  final double? rating;
  final int reviewCount;
  final DateTime nextSessionAt;
  final String nextSessionId;
  final int nextSessionFree;
  final double? distanceKm;

  factory EventCard.fromJson(Map<String, dynamic> j) => EventCard(
        id: _s(j, 'id'),
        title: _s(j, 'title'),
        venueName: _s(j, 'venueName'),
        district: j['district'] as String? ?? '',
        address: j['address'] as String? ?? '',
        categoryCode: _s(j, 'categoryCode'),
        bookingType: BookingType.parse(_s(j, 'bookingType')),
        photoUrl: j['photoUrl'] as String?,
        minPriceMinor: _i(j, 'minPriceMinor'),
        minAge: _i(j, 'minAge'),
        familyFriendly: j['familyFriendly'] == true,
        rating: (j['rating'] as num?)?.toDouble(),
        reviewCount: _i(j, 'reviewCount'),
        nextSessionAt: venueTime(_s(j, 'nextSessionAt')),
        nextSessionId: _s(j, 'nextSessionId'),
        nextSessionFree: _i(j, 'nextSessionFree'),
        distanceKm: (j['distanceKm'] as num?)?.toDouble(),
      );
}

class TicketType {
  const TicketType({
    required this.id,
    required this.name,
    required this.priceMinor,
    required this.perBooking,
    required this.zone,
  });

  final String id;
  final String name;
  final int priceMinor;
  final bool perBooking;
  final String? zone;

  factory TicketType.fromJson(Map<String, dynamic> j) => TicketType(
        id: _s(j, 'id'),
        name: _s(j, 'name'),
        priceMinor: _i(j, 'priceMinor'),
        perBooking: j['pricing'] == 'PER_BOOKING',
        zone: j['zone'] as String? ?? j['seatZone'] as String?,
      );
}

class VenueInfo {
  const VenueInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.address,
    required this.district,
    required this.latitude,
    required this.longitude,
    required this.photos,
    required this.rules,
    required this.cancellationHours,
  });

  final String id;
  final String name;
  final String description;
  final String address;
  final String district;
  final double? latitude;
  final double? longitude;
  final List<String> photos;
  final String rules;
  final int cancellationHours;

  factory VenueInfo.fromJson(Map<String, dynamic> j) => VenueInfo(
        id: _s(j, 'id'),
        name: _s(j, 'name'),
        description: j['description'] as String? ?? '',
        address: j['address'] as String? ?? '',
        district: j['district'] as String? ?? '',
        latitude: (j['latitude'] as num?)?.toDouble(),
        longitude: (j['longitude'] as num?)?.toDouble(),
        photos: _strings(j['photos']),
        rules: j['rules'] as String? ?? '',
        cancellationHours: _i(j, 'cancellationHours'),
      );
}

class EventDetail {
  const EventDetail({
    required this.id,
    required this.title,
    required this.description,
    required this.photos,
    required this.category,
    required this.bookingType,
    required this.durationMinutes,
    required this.minAge,
    required this.familyFriendly,
    required this.maxGuests,
    required this.manualConfirmation,
    required this.venue,
    required this.organizer,
    required this.ticketTypes,
    required this.rating,
    required this.reviewCount,
    required this.bookable,
    required this.demo,
  });

  final String id;
  final String title;
  final String description;
  final List<String> photos;
  final LeisureCategory category;
  final BookingType bookingType;
  final int durationMinutes;
  final int minAge;
  final bool familyFriendly;
  final int maxGuests;
  final bool manualConfirmation;
  final VenueInfo venue;
  final String organizer;
  final List<TicketType> ticketTypes;
  final double? rating;
  final int reviewCount;
  final bool bookable;
  final bool demo;

  int get fromPriceMinor => ticketTypes.isEmpty
      ? 0
      : ticketTypes.map((t) => t.priceMinor).reduce((a, b) => a < b ? a : b);

  factory EventDetail.fromJson(Map<String, dynamic> j) => EventDetail(
        id: _s(j, 'id'),
        title: _s(j, 'title'),
        description: j['description'] as String? ?? '',
        photos: _strings(j['photos']),
        category:
            LeisureCategory.fromJson(j['category'] as Map<String, dynamic>),
        bookingType: BookingType.parse(_s(j, 'bookingType')),
        durationMinutes: _i(j, 'durationMinutes'),
        minAge: _i(j, 'minAge'),
        familyFriendly: j['familyFriendly'] == true,
        maxGuests: _i(j, 'maxGuests'),
        manualConfirmation: j['confirmation'] == 'MANUAL',
        venue: VenueInfo.fromJson(j['venue'] as Map<String, dynamic>),
        organizer: j['organizer'] as String? ?? '',
        ticketTypes: [
          for (final t in j['ticketTypes'] as List<dynamic>)
            TicketType.fromJson(t as Map<String, dynamic>)
        ],
        rating: (j['rating'] as num?)?.toDouble(),
        reviewCount: _i(j, 'reviewCount'),
        bookable: j['bookable'] == true,
        demo: j['demo'] == true,
      );
}

class SessionInfo {
  const SessionInfo({
    required this.id,
    required this.startsAt,
    required this.endsAt,
    required this.capacity,
    required this.free,
    required this.fromPriceMinor,
  });

  final String id;
  final DateTime startsAt;
  final DateTime endsAt;
  final int capacity;
  final int free;
  final int fromPriceMinor;

  factory SessionInfo.fromJson(Map<String, dynamic> j) => SessionInfo(
        id: _s(j, 'id'),
        startsAt: venueTime(_s(j, 'startsAt')),
        endsAt: venueTime(_s(j, 'endsAt')),
        capacity: _i(j, 'capacity'),
        free: _i(j, 'free'),
        fromPriceMinor: _i(j, 'fromPriceMinor'),
      );
}

enum SeatState { free, held, sold }

class SeatInfo {
  const SeatInfo({
    required this.id,
    required this.row,
    required this.number,
    required this.zone,
    required this.state,
    required this.priceMinor,
  });

  final String id;
  final String row;
  final int number;
  final String zone;
  final SeatState state;
  final int? priceMinor;

  String get label => '$row$number';

  factory SeatInfo.fromJson(Map<String, dynamic> j) => SeatInfo(
        id: _s(j, 'id'),
        row: _s(j, 'row'),
        number: _i(j, 'number'),
        zone: j['zone'] as String? ?? 'STANDARD',
        state: switch (j['status']) {
          'SOLD' => SeatState.sold,
          'HELD' => SeatState.held,
          _ => SeatState.free,
        },
        priceMinor: (j['priceMinor'] as num?)?.toInt(),
      );
}

class HoldLine {
  const HoldLine(
      {required this.ticketType, required this.seat, required this.priceMinor});

  final String ticketType;
  final String? seat;
  final int priceMinor;

  factory HoldLine.fromJson(Map<String, dynamic> j) => HoldLine(
        ticketType: _s(j, 'ticketType'),
        seat: j['seat'] as String?,
        priceMinor: _i(j, 'unitPriceMinor'),
      );
}

class Hold {
  const Hold({
    required this.id,
    required this.sessionId,
    required this.guests,
    required this.totalMinor,
    required this.expiresAt,
    required this.lines,
  });

  final String id;
  final String sessionId;
  final int guests;
  final int totalMinor;
  final DateTime expiresAt;
  final List<HoldLine> lines;

  factory Hold.fromJson(Map<String, dynamic> j) => Hold(
        id: _s(j, 'id'),
        sessionId: _s(j, 'sessionId'),
        guests: _i(j, 'guests'),
        totalMinor: _i(j, 'totalMinor'),
        expiresAt: DateTime.parse(_s(j, 'expiresAt')),
        lines: [
          for (final l in j['lines'] as List<dynamic>)
            HoldLine.fromJson(l as Map<String, dynamic>)
        ],
      );
}

class Ticket {
  const Ticket({
    required this.id,
    required this.status,
    required this.ticketType,
    required this.seat,
    required this.admits,
    required this.priceMinor,
    required this.qr,
  });

  final String id;
  final String status;
  final String ticketType;
  final String? seat;
  final int admits;
  final int priceMinor;

  /// `KT1.<id>.<secret>`, only for confirmed tickets; the server checks it at the gate.
  final String? qr;

  String get shortId => id.substring(0, 8).toUpperCase();

  factory Ticket.fromJson(Map<String, dynamic> j) => Ticket(
        id: _s(j, 'id'),
        status: _s(j, 'status'),
        ticketType: _s(j, 'ticketType'),
        seat: j['seat'] as String?,
        admits: _i(j, 'admits'),
        priceMinor: _i(j, 'priceMinor'),
        qr: j['qr'] as String?,
      );
}

class LeisureOrder {
  const LeisureOrder({
    required this.id,
    required this.status,
    required this.phase,
    required this.eventId,
    required this.eventTitle,
    required this.categoryCode,
    required this.bookingType,
    required this.venueId,
    required this.venueName,
    required this.venueAddress,
    required this.photoUrl,
    required this.startsAt,
    required this.endsAt,
    required this.guests,
    required this.totalMinor,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.refundedMinor,
    required this.cancellable,
    required this.cancelUntil,
    required this.cancelledBy,
    required this.cancelReason,
    required this.rules,
    required this.minAge,
    required this.reviewed,
    required this.canReview,
    required this.tickets,
  });

  final String id;
  final String status;
  final String phase;
  final String eventId;
  final String eventTitle;
  final String categoryCode;
  final BookingType bookingType;
  final String venueId;
  final String venueName;
  final String venueAddress;
  final String? photoUrl;
  final DateTime startsAt;
  final DateTime endsAt;
  final int guests;
  final int totalMinor;
  final String paymentMethod;
  final String? paymentStatus;
  final int refundedMinor;
  final bool cancellable;
  final DateTime cancelUntil;
  final String? cancelledBy;
  final String? cancelReason;
  final String rules;
  final int minAge;
  final bool reviewed;
  final bool canReview;
  final List<Ticket> tickets;

  bool get pending => status == 'PENDING';
  bool get cancelled => status == 'CANCELLED';
  bool get testPayment => paymentMethod == 'TEST_CARD';
  String get shortId => id.substring(0, 8).toUpperCase();

  String get seats => tickets.map((t) => t.seat).whereType<String>().join(', ');

  factory LeisureOrder.fromJson(Map<String, dynamic> j) {
    final payment = j['payment'] as Map<String, dynamic>?;
    return LeisureOrder(
      id: _s(j, 'id'),
      status: _s(j, 'status'),
      phase: _s(j, 'phase'),
      eventId: _s(j, 'eventId'),
      eventTitle: _s(j, 'eventTitle'),
      categoryCode: _s(j, 'categoryCode'),
      bookingType: BookingType.parse(_s(j, 'bookingType')),
      venueId: _s(j, 'venueId'),
      venueName: _s(j, 'venueName'),
      venueAddress: j['venueAddress'] as String? ?? '',
      photoUrl: j['photoUrl'] as String?,
      startsAt: venueTime(_s(j, 'startsAt')),
      endsAt: venueTime(_s(j, 'endsAt')),
      guests: _i(j, 'guests'),
      totalMinor: _i(j, 'totalMinor'),
      paymentMethod: _s(j, 'paymentMethod'),
      paymentStatus: payment?['status'] as String?,
      refundedMinor: (payment?['refundedMinor'] as num?)?.toInt() ?? 0,
      cancellable: j['cancellable'] == true,
      cancelUntil: venueTime(_s(j, 'cancelUntil')),
      cancelledBy: j['cancelledBy'] as String?,
      cancelReason: j['cancelReason'] as String?,
      rules: j['rules'] as String? ?? '',
      minAge: _i(j, 'minAge'),
      reviewed: j['reviewed'] == true,
      canReview: j['canReview'] == true,
      tickets: [
        for (final t in j['tickets'] as List<dynamic>)
          Ticket.fromJson(t as Map<String, dynamic>)
      ],
    );
  }
}

class Review {
  const Review(
      {required this.rating, required this.body, required this.createdAt});

  final int rating;
  final String body;
  final DateTime createdAt;

  factory Review.fromJson(Map<String, dynamic> j) => Review(
        rating: _i(j, 'rating'),
        body: j['body'] as String? ?? '',
        createdAt: venueTime(_s(j, 'createdAt')),
      );
}

/// Filters of the catalogue list; every field maps to a server query parameter, nothing is filtered on the phone.
class LeisureFilter {
  const LeisureFilter({
    this.query = '',
    this.category,
    this.district,
    this.date,
    this.preset,
    this.minPriceMinor,
    this.maxPriceMinor,
    this.age,
    this.guests,
    this.availableOnly = false,
    this.family = false,
    this.minRating,
    this.sort = 'time',
    this.lat,
    this.lng,
    this.radiusKm,
  });

  final String query;
  final String? category;
  final String? district;
  final DateTime? date;
  final String? preset;
  final int? minPriceMinor;
  final int? maxPriceMinor;
  final int? age;
  final int? guests;
  final bool availableOnly;
  final bool family;
  final double? minRating;
  final String sort;
  final double? lat;
  final double? lng;
  final double? radiusKm;

  int get activeCount =>
      (minPriceMinor != null || maxPriceMinor != null ? 1 : 0) +
      (age != null ? 1 : 0) +
      (guests != null ? 1 : 0) +
      (availableOnly ? 1 : 0) +
      (family ? 1 : 0) +
      (minRating != null ? 1 : 0) +
      (date != null ? 1 : 0) +
      (radiusKm != null ? 1 : 0);

  static const _unset = Object();

  LeisureFilter copyWith({
    String? query,
    Object? category = _unset,
    Object? district = _unset,
    Object? date = _unset,
    Object? preset = _unset,
    Object? minPriceMinor = _unset,
    Object? maxPriceMinor = _unset,
    Object? age = _unset,
    Object? guests = _unset,
    bool? availableOnly,
    bool? family,
    Object? minRating = _unset,
    String? sort,
    Object? lat = _unset,
    Object? lng = _unset,
    Object? radiusKm = _unset,
  }) =>
      LeisureFilter(
        query: query ?? this.query,
        category:
            identical(category, _unset) ? this.category : category as String?,
        district:
            identical(district, _unset) ? this.district : district as String?,
        date: identical(date, _unset) ? this.date : date as DateTime?,
        preset: identical(preset, _unset) ? this.preset : preset as String?,
        minPriceMinor: identical(minPriceMinor, _unset)
            ? this.minPriceMinor
            : minPriceMinor as int?,
        maxPriceMinor: identical(maxPriceMinor, _unset)
            ? this.maxPriceMinor
            : maxPriceMinor as int?,
        age: identical(age, _unset) ? this.age : age as int?,
        guests: identical(guests, _unset) ? this.guests : guests as int?,
        availableOnly: availableOnly ?? this.availableOnly,
        family: family ?? this.family,
        minRating: identical(minRating, _unset)
            ? this.minRating
            : minRating as double?,
        sort: sort ?? this.sort,
        lat: identical(lat, _unset) ? this.lat : lat as double?,
        lng: identical(lng, _unset) ? this.lng : lng as double?,
        radiusKm:
            identical(radiusKm, _unset) ? this.radiusKm : radiusKm as double?,
      );
}
