import '../../app/ops_store.dart';
import '../../core/format.dart';
import '../../data/models.dart';

/// One line of the "recent events" feed.
class FeedEvent {
  const FeedEvent({
    required this.at,
    required this.isOrder,
    required this.ref,
    required this.status,
    this.actor,
    this.title,
  });
  final DateTime at;
  final bool isOrder;
  final String ref; // short order number or service name
  final String status;
  final String? actor;
  final String? title;
}

/// Numbers shown on the dashboard. Everything is derived from lists the API
/// already returns; nothing is estimated. [revenueComplete] is false when the
/// loaded history page might not cover the whole day.
class DashboardStats {
  const DashboardStats({
    required this.newOrders,
    required this.activeOrders,
    required this.pendingRequests,
    required this.upcomingBookings,
    required this.completedOrdersToday,
    required this.completedBookingsToday,
    required this.revenueTodayMinor,
    required this.revenueComplete,
    required this.soonestDeadline,
    required this.events,
  });

  final int newOrders;
  final int activeOrders;
  final int pendingRequests;
  final int upcomingBookings;
  final int completedOrdersToday;
  final int completedBookingsToday;
  final int revenueTodayMinor;
  final bool revenueComplete;
  final DateTime? soonestDeadline;
  final List<FeedEvent> events;

  int get attention => newOrders + pendingRequests;
  int get completedToday => completedOrdersToday + completedBookingsToday;

  static DashboardStats from(OpsStore store, DateTime now) {
    final active = store.activeOrders.data ?? const <PartnerOrder>[];
    final history = store.historyOrders.data ?? const <PartnerOrder>[];
    final requests = store.bookingRequests.data ?? const <PartnerBooking>[];
    final upcoming = store.bookingUpcoming.data ?? const <PartnerBooking>[];
    final bookingHistory =
        store.bookingHistory.data ?? const <PartnerBooking>[];

    final newOrders = active.where((o) => o.isNew).toList();
    final deliveredToday = history.where((o) {
      final t = o.finishedAt;
      return o.status == 'DELIVERED' && t != null && sameDay(t, now);
    }).toList();
    final revenue = deliveredToday.fold<int>(0, (a, o) => a + o.totalMinor);

    // The history page is newest-first. If its oldest loaded entry is still
    // from today (and more pages exist), today's total may be incomplete.
    var complete = true;
    if (store.orderHistoryHasMore && history.isNotEmpty) {
      final oldest = history.last.finishedAt;
      complete =
          oldest != null && !sameDay(oldest, now) && oldest.isBefore(now);
    }

    final completedBookings = bookingHistory.where((b) {
      if (b.status != 'COMPLETED') return false;
      final t = b.endsAt ?? b.startsAt;
      return t != null && sameDay(t, now);
    }).length;

    DateTime? soonest;
    for (final o in newOrders) {
      final d = o.respondBy;
      if (d != null && (soonest == null || d.isBefore(soonest))) soonest = d;
    }

    final events = <FeedEvent>[
      for (final o in [...active, ...history])
        for (final e in o.timeline)
          if (e.at != null)
            FeedEvent(
              at: e.at!,
              isOrder: true,
              ref: o.shortRef,
              status: e.status,
              actor: e.actor,
              title: o.restaurantName,
            ),
      for (final b in [...requests, ...upcoming, ...bookingHistory])
        for (final e in b.timeline)
          if (e.at != null)
            FeedEvent(
              at: e.at!,
              isOrder: false,
              ref: b.serviceName,
              status: e.status,
              actor: e.actor,
              title: b.venueName,
            ),
    ]..sort((a, b) => b.at.compareTo(a.at));

    return DashboardStats(
      newOrders: newOrders.length,
      activeOrders: active.length - newOrders.length,
      pendingRequests: requests.length,
      upcomingBookings: upcoming.length,
      completedOrdersToday: deliveredToday.length,
      completedBookingsToday: completedBookings,
      revenueTodayMinor: revenue,
      revenueComplete: complete,
      soonestDeadline: soonest,
      events: events.take(8).toList(),
    );
  }
}
