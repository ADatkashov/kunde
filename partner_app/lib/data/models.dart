/// Typed views of the Partner Operations API. Parsing is tolerant of missing
/// optional fields but strict about identity, so a malformed record is
/// rejected instead of being shown half-empty.
library;

String? _str(Object? v) => v is String && v.isNotEmpty ? v : null;
int _int(Object? v) => v is num ? v.toInt() : 0;
bool _bool(Object? v, [bool fallback = false]) => v is bool ? v : fallback;
DateTime? _time(Object? v) =>
    v is String ? DateTime.tryParse(v)?.toLocal() : null;

String _id(Map<String, dynamic> j, String what) {
  final v = _str(j['id']);
  if (v == null) throw FormatException('$what without id');
  return v;
}

List<String> _strings(Object? v) =>
    v is List ? v.whereType<String>().toList() : const [];

List<T> _list<T>(Object? v, T Function(Map<String, dynamic>) f) =>
    v is List ? v.whereType<Map<String, dynamic>>().map(f).toList() : <T>[];

class PartnerMembership {
  const PartnerMembership({
    required this.id,
    required this.name,
    required this.status,
    required this.role,
  });

  factory PartnerMembership.fromJson(Map<String, dynamic> j) =>
      PartnerMembership(
        id: _id(j, 'partner'),
        name: _str(j['displayName']) ?? _str(j['name']) ?? '',
        status: _str(j['verificationStatus']) ?? '',
        role: _str(j['role']) ?? '',
      );

  final String id;
  final String name;
  final String status;
  final String role;

  bool get approved => status == 'APPROVED';
  bool get isOwner => role == 'OWNER';

  /// Owner/Manager may edit prices, hours and the open state.
  bool get canManage => role == 'OWNER' || role == 'MANAGER';
}

class TimelineEntry {
  const TimelineEntry({required this.status, this.at, this.actor, this.reason});
  factory TimelineEntry.fromJson(Map<String, dynamic> j) => TimelineEntry(
        status: _str(j['status']) ?? '',
        at: _time(j['at']),
        actor: _str(j['actor']),
        reason: _str(j['reason']),
      );
  final String status;
  final DateTime? at;
  final String? actor;
  final String? reason;
}

class OrderLine {
  const OrderLine({
    required this.name,
    required this.quantity,
    required this.lineTotalMinor,
    this.optionsText,
    this.unit,
  });
  factory OrderLine.fromJson(Map<String, dynamic> j) => OrderLine(
        name: _str(j['name']) ?? '',
        quantity: _int(j['quantity']),
        lineTotalMinor: _int(j['finalLineTotalMinor'] ?? j['lineTotalMinor']),
        optionsText: _str(j['optionsText']),
        unit: _str(j['unit']),
      );
  final String name;
  final int quantity;
  final int lineTotalMinor;
  final String? optionsText;
  final String? unit;
}

class PartnerOrder {
  const PartnerOrder({
    required this.id,
    required this.status,
    required this.restaurantName,
    required this.totalMinor,
    required this.subtotalMinor,
    required this.deliveryFeeMinor,
    required this.currency,
    required this.items,
    required this.timeline,
    required this.allowedNext,
    this.placedAt,
    this.respondBy,
    this.comment,
    this.addressText,
    this.paymentMethod,
    this.paymentStatus,
    this.cancelReason,
    this.cancelledBy,
  });

  /// Parses an inbox entry `{order, allowedNext, respondBy, …}`.
  factory PartnerOrder.fromJson(Map<String, dynamic> entry) {
    final o = entry['order'];
    if (o is! Map<String, dynamic>) {
      throw const FormatException('order entry without order');
    }
    return PartnerOrder(
      id: _id(o, 'order'),
      status: _str(o['status']) ?? '',
      restaurantName: _str(o['restaurantName']) ?? '',
      totalMinor: _int(o['finalTotalMinor'] ?? o['totalMinor']),
      subtotalMinor: _int(o['subtotalMinor']),
      deliveryFeeMinor: _int(o['deliveryFeeMinor']),
      currency: _str(o['currency']) ?? 'KZT',
      items: _list(o['items'], OrderLine.fromJson),
      timeline: _list(o['timeline'], TimelineEntry.fromJson),
      allowedNext: _strings(entry['allowedNext']),
      placedAt: _time(o['placedAt']),
      respondBy: _time(entry['respondBy']),
      comment: _str(o['comment']),
      addressText: _str(o['addressText']),
      paymentMethod: _str(o['paymentMethod']),
      paymentStatus: _str(o['paymentStatus']),
      cancelReason: _str(o['cancelReason']),
      cancelledBy: _str(o['cancelledBy']),
    );
  }

  final String id;
  final String status;
  final String restaurantName;
  final int totalMinor;
  final int subtotalMinor;
  final int deliveryFeeMinor;
  final String currency;
  final List<OrderLine> items;
  final List<TimelineEntry> timeline;
  final List<String> allowedNext;
  final DateTime? placedAt;
  final DateTime? respondBy;
  final String? comment;
  final String? addressText;
  final String? paymentMethod;
  final String? paymentStatus;
  final String? cancelReason;
  final String? cancelledBy;

  bool get isNew => status == 'PLACED';
  bool get isActive =>
      const {'PLACED', 'ACCEPTED', 'PREPARING', 'ON_THE_WAY'}.contains(status);
  int get itemCount => items.fold(0, (a, l) => a + l.quantity);

  /// Short human reference derived from the id; never the full identifier.
  String get shortRef => id.replaceAll('-', '').substring(0, 6).toUpperCase();

  /// When the terminal state was reached (for "today" statistics).
  DateTime? get finishedAt {
    for (final e in timeline.reversed) {
      if ((e.status == 'DELIVERED' || e.status == 'CANCELLED') &&
          e.at != null) {
        return e.at;
      }
    }
    return placedAt;
  }
}

class PartnerBooking {
  const PartnerBooking({
    required this.id,
    required this.status,
    required this.venueName,
    required this.serviceName,
    required this.durationMinutes,
    required this.priceMinor,
    required this.currency,
    required this.allowedActions,
    required this.timeline,
    this.masterName,
    this.startsAt,
    this.endsAt,
    this.comment,
    this.addressText,
    this.createdAt,
    this.cancelledBy,
    this.cancelReason,
  });

  factory PartnerBooking.fromJson(Map<String, dynamic> j) => PartnerBooking(
        id: _id(j, 'booking'),
        status: _str(j['status']) ?? '',
        venueName: _str(j['venueName']) ?? '',
        serviceName: _str(j['serviceName']) ?? '',
        durationMinutes: _int(j['durationMinutes']),
        priceMinor: _int(j['priceMinor']),
        currency: _str(j['currency']) ?? 'KZT',
        allowedActions: _strings(j['allowedActions']),
        timeline: _list(j['timeline'], TimelineEntry.fromJson),
        masterName: _str(j['masterName']),
        startsAt: _time(j['startsAt']),
        endsAt: _time(j['endsAt']),
        comment: _str(j['comment']),
        addressText: _str(j['addressText']),
        createdAt: _time(j['createdAt']),
        cancelledBy: _str(j['cancelledBy']),
        cancelReason: _str(j['cancelReason']),
      );

  final String id;
  final String status;
  final String venueName;
  final String serviceName;
  final int durationMinutes;
  final int priceMinor;
  final String currency;
  final List<String> allowedActions;
  final List<TimelineEntry> timeline;
  final String? masterName;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String? comment;
  final String? addressText;
  final DateTime? createdAt;
  final String? cancelledBy;
  final String? cancelReason;

  bool get isPending => status == 'PENDING';
}

class Restaurant {
  const Restaurant({required this.id, required this.name, required this.open});
  factory Restaurant.fromJson(Map<String, dynamic> j) => Restaurant(
      id: _id(j, 'restaurant'),
      name: _str(j['name']) ?? '',
      open: _bool(j['open']));
  final String id;
  final String name;
  final bool open;
}

class Dish {
  const Dish({
    required this.id,
    required this.name,
    required this.section,
    required this.sectionId,
    required this.priceMinor,
    required this.available,
    this.stockQty,
    this.description,
  });
  factory Dish.fromJson(Map<String, dynamic> j) => Dish(
        id: _id(j, 'dish'),
        name: _str(j['name']) ?? '',
        section: _str(j['section']) ?? '',
        sectionId: _str(j['sectionId']),
        priceMinor: _int(j['priceMinor']),
        available: _bool(j['available']),
        stockQty: j['stockQty'] is num ? (j['stockQty'] as num).toInt() : null,
        description: _str(j['description']),
      );
  final String id;
  final String name;
  final String section;
  final String? sectionId;
  final int priceMinor;
  final bool available;
  final int? stockQty;
  final String? description;
}

class Venue {
  const Venue({required this.id, required this.name, required this.open});
  factory Venue.fromJson(Map<String, dynamic> j) => Venue(
      id: _id(j, 'venue'), name: _str(j['name']) ?? '', open: _bool(j['open']));
  final String id;
  final String name;
  final bool open;
}

class VenueService {
  const VenueService({
    required this.id,
    required this.name,
    required this.durationMinutes,
    required this.priceMinor,
    required this.available,
  });
  factory VenueService.fromJson(Map<String, dynamic> j) => VenueService(
        id: _id(j, 'service'),
        name: _str(j['name']) ?? '',
        durationMinutes: _int(j['durationMinutes']),
        priceMinor: _int(j['priceMinor']),
        available: _bool(j['available']),
      );
  final String id;
  final String name;
  final int durationMinutes;
  final int priceMinor;
  final bool available;
}

class WorkingHours {
  const WorkingHours({
    required this.day,
    required this.from,
    required this.to,
    this.breakFrom,
    this.breakTo,
  });
  factory WorkingHours.fromJson(Map<String, dynamic> j) => WorkingHours(
        day: _int(j['day']),
        from: _str(j['from']) ?? '',
        to: _str(j['to']) ?? '',
        breakFrom: _str(j['breakFrom']),
        breakTo: _str(j['breakTo']),
      );

  Map<String, dynamic> toJson() => {
        'day': day,
        'from': from,
        'to': to,
        if (breakFrom != null) 'breakFrom': breakFrom,
        if (breakTo != null) 'breakTo': breakTo,
      };

  /// ISO weekday 1 (Mon) … 7 (Sun).
  final int day;
  final String from;
  final String to;
  final String? breakFrom;
  final String? breakTo;
}

class Master {
  const Master(
      {required this.id,
      required this.name,
      required this.active,
      required this.hours});
  factory Master.fromJson(Map<String, dynamic> j) => Master(
        id: _id(j, 'master'),
        name: _str(j['name']) ?? '',
        active: _bool(j['active']),
        hours: _list(j['hours'], WorkingHours.fromJson),
      );
  final String id;
  final String name;
  final bool active;
  final List<WorkingHours> hours;
}
