import '../../identity/auth_repository.dart';
import 'beauty_models.dart';

/// Beauty operations for KUNDE Partner (salon), Executor (master) and Admin. Own-data endpoints only.
class BeautyOpsApi {
  const BeautyOpsApi(this.auth);

  final AuthRepository auth;

  // ---- Partner ----------------------------------------------------------------------------

  Future<BeautyOverview> overview(String partnerId) async =>
      BeautyOverview.fromJson((await auth.authorizedJson(
              'GET', 'partner/partners/$partnerId/beauty/overview'))
          as Map<String, dynamic>);

  Future<List<BeautyMasterRow>> masters(String partnerId) async =>
      ((await auth.authorizedJson(
                  'GET', 'partner/partners/$partnerId/beauty/masters'))
              as List<dynamic>)
          .map((e) => BeautyMasterRow.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);

  // ---- Executor (master) --------------------------------------------------------------------

  /// Null when this account is not linked to a master yet (`NOT_A_MASTER`).
  Future<BeautyToday?> today() async {
    try {
      return BeautyToday.fromJson((await auth.authorizedJson(
          'GET', 'executor/beauty/today')) as Map<String, dynamic>);
    } on IdentityApiError catch (error) {
      if (error.code == 'NOT_A_MASTER') return null;
      rethrow;
    }
  }

  Future<void> link(String code) =>
      auth.authorizedJson('POST', 'executor/beauty/link',
          body: {'code': code.trim()}, expected: const {204});

  Future<void> setOnline(bool online) =>
      auth.authorizedJson('PUT', 'executor/beauty/availability',
          body: {'online': online}, expected: const {204});

  /// [step] is `start`, `complete` or `no-show`.
  Future<void> step(String appointmentId, String step) => auth.authorizedJson(
      'POST', 'executor/beauty/appointments/$appointmentId/$step',
      expected: const {204});

  Future<BeautyEarnings> earnings() async => BeautyEarnings.fromJson(
      (await auth.authorizedJson('GET', 'executor/beauty/earnings'))
          as Map<String, dynamic>);

  Future<List<BeautyCategory>> categories() async =>
      ((await auth.authorizedJson('GET', 'beauty/categories?limit=50'))
              as List<dynamic>)
          .map((e) => BeautyCategory.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);

  // ---- Admin ----------------------------------------------------------------------------------

  Future<BeautyAnalytics> analytics({int days = 7}) async =>
      BeautyAnalytics.fromJson((await auth.authorizedJson(
          'GET', 'admin/beauty/analytics?days=$days')) as Map<String, dynamic>);
}

int? _int(Object? v) => (v as num?)?.toInt();

class BeautySalonRef {
  const BeautySalonRef(
      {required this.id, required this.name, required this.addressText});

  final String id;
  final String name;
  final String addressText;

  factory BeautySalonRef.fromJson(Map<String, dynamic> json) => BeautySalonRef(
        id: json['id'] as String,
        name: json['name'] as String,
        addressText: json['addressText'] as String? ?? '',
      );
}

class BeautyOverview {
  const BeautyOverview({
    required this.salons,
    required this.bookingsToday,
    required this.revenueTodayMinor,
    required this.pendingRequests,
    required this.mastersOnline,
    required this.mastersTotal,
    this.bookingsDeltaPercent,
    this.revenueDeltaPercent,
  });

  final List<BeautySalonRef> salons;
  final int bookingsToday;
  final int? bookingsDeltaPercent;
  final int revenueTodayMinor;
  final int? revenueDeltaPercent;
  final int pendingRequests;
  final int mastersOnline;
  final int mastersTotal;

  factory BeautyOverview.fromJson(Map<String, dynamic> json) => BeautyOverview(
        salons: [
          for (final s in json['salons'] as List<dynamic>)
            BeautySalonRef.fromJson(s as Map<String, dynamic>)
        ],
        bookingsToday: _int(json['bookingsToday']) ?? 0,
        bookingsDeltaPercent: _int(json['bookingsDeltaPercent']),
        revenueTodayMinor: _int(json['revenueTodayMinor']) ?? 0,
        revenueDeltaPercent: _int(json['revenueDeltaPercent']),
        pendingRequests: _int(json['pendingRequests']) ?? 0,
        mastersOnline: _int(json['mastersOnline']) ?? 0,
        mastersTotal: _int(json['mastersTotal']) ?? 0,
      );
}

class BeautyMasterRow {
  const BeautyMasterRow({
    required this.id,
    required this.name,
    required this.specialty,
    required this.online,
    required this.linked,
    this.inviteCode,
  });

  final String id;
  final String name;
  final String specialty;
  final bool online;
  final bool linked;

  /// Shown only until the master links an account with it.
  final String? inviteCode;

  factory BeautyMasterRow.fromJson(Map<String, dynamic> json) =>
      BeautyMasterRow(
        id: json['id'] as String,
        name: json['name'] as String,
        specialty: json['specialty'] as String? ?? '',
        online: json['online'] == true,
        linked: json['linked'] == true,
        inviteCode: json['inviteCode'] as String?,
      );
}

class BeautyAppointment {
  const BeautyAppointment({
    required this.id,
    required this.bookingNumber,
    required this.serviceName,
    required this.venueName,
    required this.clientName,
    required this.start,
    required this.end,
    required this.status,
    required this.canStart,
    required this.canComplete,
    required this.canMarkNoShow,
  });

  final String id;
  final String bookingNumber;
  final String serviceName;
  final String venueName;
  final String clientName;
  final DateTime start;
  final DateTime end;
  final String status;
  final bool canStart;
  final bool canComplete;
  final bool canMarkNoShow;

  static DateTime _wall(String iso) {
    final m =
        RegExp(r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})').firstMatch(iso);
    if (m == null) throw FormatException('Invalid timestamp: $iso');
    return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!),
        int.parse(m[4]!), int.parse(m[5]!));
  }

  factory BeautyAppointment.fromJson(Map<String, dynamic> json) =>
      BeautyAppointment(
        id: json['id'] as String,
        bookingNumber: json['bookingNumber'] as String? ?? '',
        serviceName: json['serviceName'] as String,
        venueName: json['venueName'] as String,
        clientName: json['clientName'] as String? ?? '',
        start: _wall(json['startsAt'] as String),
        end: _wall(json['endsAt'] as String),
        status: json['status'] as String,
        canStart: json['canStart'] == true,
        canComplete: json['canComplete'] == true,
        canMarkNoShow: json['canMarkNoShow'] == true,
      );
}

class BeautyToday {
  const BeautyToday({
    required this.masterName,
    required this.venueName,
    required this.online,
    required this.todayCount,
    required this.appointments,
  });

  final String masterName;
  final String venueName;
  final bool online;
  final int todayCount;
  final List<BeautyAppointment> appointments;

  factory BeautyToday.fromJson(Map<String, dynamic> json) => BeautyToday(
        masterName: json['masterName'] as String,
        venueName: json['venueName'] as String,
        online: json['online'] == true,
        todayCount: _int(json['todayCount']) ?? 0,
        appointments: [
          for (final a in json['appointments'] as List<dynamic>)
            BeautyAppointment.fromJson(a as Map<String, dynamic>)
        ],
      );
}

class BeautyEarnings {
  const BeautyEarnings({
    required this.todayMinor,
    required this.weekMinor,
    required this.monthMinor,
    required this.completedToday,
    required this.completedMonth,
  });

  final int todayMinor;
  final int weekMinor;
  final int monthMinor;
  final int completedToday;
  final int completedMonth;

  factory BeautyEarnings.fromJson(Map<String, dynamic> json) => BeautyEarnings(
        todayMinor: _int(json['todayMinor']) ?? 0,
        weekMinor: _int(json['weekMinor']) ?? 0,
        monthMinor: _int(json['monthMinor']) ?? 0,
        completedToday: _int(json['completedToday']) ?? 0,
        completedMonth: _int(json['completedMonth']) ?? 0,
      );
}

class BeautyDayCount {
  const BeautyDayCount(this.date, this.bookings);

  final String date;
  final int bookings;
}

class BeautyCategoryShare {
  const BeautyCategoryShare(this.code, this.bookings, this.percent);

  final String code;
  final int bookings;
  final int percent;
}

class BeautyRecent {
  const BeautyRecent({
    required this.bookingNumber,
    required this.client,
    required this.salon,
    required this.service,
    required this.amountMinor,
    required this.status,
  });

  final String bookingNumber;
  final String client;
  final String salon;
  final String service;
  final int amountMinor;
  final String status;
}

class BeautyAnalytics {
  const BeautyAnalytics({
    required this.days,
    required this.salons,
    required this.bookings,
    required this.revenueMinor,
    required this.averageCheckMinor,
    required this.bookingsByDay,
    required this.categories,
    required this.recent,
    this.salonsDelta,
    this.bookingsDelta,
    this.revenueDelta,
    this.averageDelta,
  });

  final int days;
  final int salons;
  final int? salonsDelta;
  final int bookings;
  final int? bookingsDelta;
  final int revenueMinor;
  final int? revenueDelta;
  final int averageCheckMinor;
  final int? averageDelta;
  final List<BeautyDayCount> bookingsByDay;
  final List<BeautyCategoryShare> categories;
  final List<BeautyRecent> recent;

  factory BeautyAnalytics.fromJson(Map<String, dynamic> json) =>
      BeautyAnalytics(
        days: _int(json['days']) ?? 7,
        salons: _int(json['salons']) ?? 0,
        salonsDelta: _int(json['salonsDeltaPercent']),
        bookings: _int(json['bookings']) ?? 0,
        bookingsDelta: _int(json['bookingsDeltaPercent']),
        revenueMinor: _int(json['revenueMinor']) ?? 0,
        revenueDelta: _int(json['revenueDeltaPercent']),
        averageCheckMinor: _int(json['averageCheckMinor']) ?? 0,
        averageDelta: _int(json['averageCheckDeltaPercent']),
        bookingsByDay: [
          for (final d in json['bookingsByDay'] as List<dynamic>)
            BeautyDayCount((d as Map<String, dynamic>)['date'] as String,
                _int(d['bookings']) ?? 0)
        ],
        categories: [
          for (final c in json['categories'] as List<dynamic>)
            BeautyCategoryShare((c as Map<String, dynamic>)['code'] as String,
                _int(c['bookings']) ?? 0, _int(c['percent']) ?? 0)
        ],
        recent: [
          for (final r in json['recent'] as List<dynamic>)
            BeautyRecent(
              bookingNumber:
                  (r as Map<String, dynamic>)['bookingNumber'] as String? ?? '',
              client: r['client'] as String? ?? '',
              salon: r['salon'] as String? ?? '',
              service: r['service'] as String? ?? '',
              amountMinor: _int(r['amountMinor']) ?? 0,
              status: r['status'] as String? ?? '',
            )
        ],
      );
}
