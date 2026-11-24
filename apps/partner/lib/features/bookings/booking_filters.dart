import '../../core/format.dart';
import '../../data/models.dart';

enum DateFilter { all, today, tomorrow, week }

/// Client-side filter over already loaded bookings (the API pages by scope,
/// not by date).
List<PartnerBooking> filterBookings(
  List<PartnerBooking> source, {
  DateFilter date = DateFilter.all,
  String? status,
  required DateTime now,
}) {
  final startOfToday = DateTime(now.year, now.month, now.day);
  bool inRange(DateTime? t) {
    if (date == DateFilter.all) return true;
    if (t == null) return false;
    switch (date) {
      case DateFilter.today:
        return sameDay(t, now);
      case DateFilter.tomorrow:
        return sameDay(t, startOfToday.add(const Duration(days: 1, hours: 12)));
      case DateFilter.week:
        return !t.isBefore(startOfToday) &&
            t.isBefore(startOfToday.add(const Duration(days: 7)));
      case DateFilter.all:
        return true;
    }
  }

  return source
      .where(
          (b) => inRange(b.startsAt) && (status == null || b.status == status))
      .toList();
}
