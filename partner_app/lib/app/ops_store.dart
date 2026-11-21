import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/errors.dart';
import '../data/models.dart';
import '../data/partner_operations.dart';

/// Result of one loadable section: last good data is kept while a refresh
/// runs or fails, so the UI never blanks out because of a flaky network.
class Loadable<T> {
  T? data;
  Object? error;
  bool loading = false;
  DateTime? updatedAt;

  bool get hasData => data != null;
  bool get failedWithoutData => error != null && data == null;
}

/// New work that arrived since the previous poll.
class NewWork {
  const NewWork({required this.orders, required this.bookings});
  final int orders;
  final int bookings;
  bool get any => orders > 0 || bookings > 0;
}

/// Single source of truth for operations data of the selected partner.
///
/// Screens read from here instead of loading on their own, so the dashboard,
/// the order list and the alert poller never fetch the same data twice.
class OpsStore extends ChangeNotifier {
  OpsStore(
    this.ops, {
    this.onFatal,
    this.pollInterval = const Duration(seconds: 20),
    this.pageSize = 30,
  });

  final PartnerOperations ops;

  /// Reports failures that mean "sign in again" / "access removed".
  final void Function(Object error)? onFatal;
  final Duration? pollInterval;
  final int pageSize;

  final activeOrders = Loadable<List<PartnerOrder>>();
  final historyOrders = Loadable<List<PartnerOrder>>();
  final bookingRequests = Loadable<List<PartnerBooking>>();
  final bookingUpcoming = Loadable<List<PartnerBooking>>();
  final bookingHistory = Loadable<List<PartnerBooking>>();
  final restaurants = Loadable<List<Restaurant>>();
  final venues = Loadable<List<Venue>>();

  bool orderHistoryHasMore = false;
  bool bookingHistoryHasMore = false;
  bool loadingMoreOrders = false;
  bool loadingMoreBookings = false;

  /// Ids with an action in flight; protects against double taps.
  final Set<String> _busy = {};
  bool isBusy(String id) => _busy.contains(id);

  /// Emits when new orders/requests appear after the first successful load.
  final ValueNotifier<NewWork?> newWork = ValueNotifier(null);

  bool _disposed = false;
  Set<String>? _seenOrders;
  Set<String>? _seenRequests;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<T?> _load<T>(Loadable<T> slot, Future<T> Function() fetch) async {
    slot.loading = true;
    _notify();
    try {
      final value = await fetch();
      slot.data = value;
      slot.error = null;
      slot.updatedAt = DateTime.now();
      return value;
    } on Object catch (e) {
      slot.error = e;
      _reportFatal(e);
      return null;
    } finally {
      slot.loading = false;
      _notify();
    }
  }

  void _reportFatal(Object e) {
    if (e is SessionExpiredException) {
      onFatal?.call(e);
    } else if (e is PartnerApiException &&
        (e.isAccessRevoked || e.kind == ApiErrorKind.unauthorized)) {
      onFatal?.call(e);
    }
  }

  // ── Orders ─────────────────────────────────────────────────────────
  Future<void> refreshActiveOrders() async {
    final rows =
        await _load(activeOrders, () => ops.orders(history: false, limit: 100));
    if (rows != null) _detectNewOrders(rows);
  }

  Future<void> refreshOrderHistory() async {
    final rows = await _load(
        historyOrders, () => ops.orders(history: true, limit: pageSize));
    if (rows != null) orderHistoryHasMore = rows.length >= pageSize;
  }

  Future<void> refreshOrders() =>
      Future.wait([refreshActiveOrders(), refreshOrderHistory()]);

  Future<void> loadMoreOrderHistory() async {
    final current = historyOrders.data;
    if (current == null || loadingMoreOrders || !orderHistoryHasMore) return;
    loadingMoreOrders = true;
    _notify();
    try {
      final more = await ops.orders(
          history: true, limit: pageSize, offset: current.length);
      final known = current.map((o) => o.id).toSet();
      historyOrders.data = [
        ...current,
        ...more.where((o) => !known.contains(o.id))
      ];
      orderHistoryHasMore = more.length >= pageSize;
    } on Object catch (e) {
      historyOrders.error = e;
      _reportFatal(e);
    } finally {
      loadingMoreOrders = false;
      _notify();
    }
  }

  // ── Bookings ───────────────────────────────────────────────────────
  Future<void> refreshBookingRequests() async {
    final rows = await _load(
        bookingRequests, () => ops.bookings(scope: 'requests', limit: 100));
    if (rows != null) _detectNewRequests(rows);
  }

  Future<void> refreshBookingUpcoming() =>
      _load(bookingUpcoming, () => ops.bookings(scope: 'upcoming', limit: 100));

  Future<void> refreshBookingHistory() async {
    final rows = await _load(
        bookingHistory, () => ops.bookings(scope: 'history', limit: pageSize));
    if (rows != null) bookingHistoryHasMore = rows.length >= pageSize;
  }

  Future<void> refreshBookings() => Future.wait([
        refreshBookingRequests(),
        refreshBookingUpcoming(),
        refreshBookingHistory(),
      ]);

  Future<void> loadMoreBookingHistory() async {
    final current = bookingHistory.data;
    if (current == null || loadingMoreBookings || !bookingHistoryHasMore) {
      return;
    }
    loadingMoreBookings = true;
    _notify();
    try {
      final more = await ops.bookings(
          scope: 'history', limit: pageSize, offset: current.length);
      final known = current.map((b) => b.id).toSet();
      bookingHistory.data = [
        ...current,
        ...more.where((b) => !known.contains(b.id))
      ];
      bookingHistoryHasMore = more.length >= pageSize;
    } on Object catch (e) {
      bookingHistory.error = e;
      _reportFatal(e);
    } finally {
      loadingMoreBookings = false;
      _notify();
    }
  }

  // ── Catalog presence (which modules this partner has) ───────────────
  Future<void> refreshModules() => Future.wait([
        _load(restaurants, ops.restaurants),
        _load(venues, ops.venues),
      ]);

  Future<void> refreshAll() => Future.wait([
        refreshOrders(),
        refreshBookings(),
        refreshModules(),
      ]);

  // ── Actions ────────────────────────────────────────────────────────
  /// Moves an order. Throws [PartnerApiException]; on a conflict the lists are
  /// refreshed so the UI shows the state the server decided on.
  Future<PartnerOrder?> changeOrder(String id, String status,
      {String? reason}) async {
    if (!_busy.add(id)) return null; // double tap
    _notify();
    try {
      final updated = await ops.updateOrder(id, status, reason: reason);
      _applyOrder(updated);
      return updated;
    } on PartnerApiException catch (e) {
      _reportFatal(e);
      if (e.kind == ApiErrorKind.conflict || e.kind == ApiErrorKind.notFound) {
        unawaited(refreshOrders());
      }
      rethrow;
    } finally {
      _busy.remove(id);
      _notify();
    }
  }

  /// Picks one line of an order (same conflict handling as [changeOrder]).
  Future<PartnerOrder?> pickLine(String orderId, String itemId, String action,
      {String? replacementDishId}) async {
    if (!_busy.add(orderId)) return null;
    _notify();
    try {
      final updated = await ops.pickItem(orderId, itemId, action,
          replacementDishId: replacementDishId);
      _applyOrder(updated);
      return updated;
    } on PartnerApiException catch (e) {
      _reportFatal(e);
      if (e.kind == ApiErrorKind.conflict || e.kind == ApiErrorKind.notFound) {
        unawaited(refreshOrders());
      }
      rethrow;
    } finally {
      _busy.remove(orderId);
      _notify();
    }
  }

  void _applyOrder(PartnerOrder o) {
    final active = [...?activeOrders.data];
    final history = [...?historyOrders.data];
    active.removeWhere((x) => x.id == o.id);
    history.removeWhere((x) => x.id == o.id);
    if (o.isActive) {
      active.insert(0, o);
      active.sort((a, b) =>
          (b.placedAt ?? DateTime(0)).compareTo(a.placedAt ?? DateTime(0)));
    } else {
      history.insert(0, o);
    }
    activeOrders.data = active;
    if (historyOrders.hasData) historyOrders.data = history;
  }

  Future<PartnerBooking?> changeBooking(String id, String action,
      {String? reason, int? finalPriceMinor}) async {
    if (!_busy.add(id)) return null;
    _notify();
    try {
      final updated = await ops.bookingAction(id, action,
          reason: reason, finalPriceMinor: finalPriceMinor);
      await Future.wait([
        refreshBookingRequests(),
        refreshBookingUpcoming(),
        refreshBookingHistory(),
      ]);
      return updated;
    } on PartnerApiException catch (e) {
      _reportFatal(e);
      if (e.kind == ApiErrorKind.conflict || e.kind == ApiErrorKind.notFound) {
        unawaited(refreshBookings());
      }
      rethrow;
    } finally {
      _busy.remove(id);
      _notify();
    }
  }

  // ── Alerts (foreground polling) ────────────────────────────────────
  void _detectNewOrders(List<PartnerOrder> rows) {
    final fresh = rows.where((o) => o.isNew).map((o) => o.id).toSet();
    final seen = _seenOrders;
    _seenOrders = {...?seen, ...fresh};
    if (seen == null) return; // first load is silent
    final added = fresh.difference(seen).length;
    if (added > 0) _emit(orders: added);
  }

  void _detectNewRequests(List<PartnerBooking> rows) {
    final fresh = rows.map((b) => b.id).toSet();
    final seen = _seenRequests;
    _seenRequests = {...?seen, ...fresh};
    if (seen == null) return;
    final added = fresh.difference(seen).length;
    if (added > 0) _emit(bookings: added);
  }

  void _emit({int orders = 0, int bookings = 0}) {
    final prev = newWork.value;
    newWork.value = NewWork(
      orders: orders + (prev?.orders ?? 0),
      bookings: bookings + (prev?.bookings ?? 0),
    );
  }

  /// Called by the UI after it has shown the alert.
  void acknowledgeNewWork() => newWork.value = null;

  Timer? _timer;
  bool _foreground = true;
  int _failures = 0;
  bool _polling = false;

  void startPolling() {
    _timer?.cancel();
    final base = pollInterval;
    if (base == null || _disposed) return;
    _schedule(base);
  }

  void _schedule(Duration base) {
    // Back off while the network is failing (20 s → 40 s → … capped at 2 min).
    final factor = 1 << _failures.clamp(0, 3);
    final next = base * factor;
    _timer = Timer(
        next > const Duration(minutes: 2) ? const Duration(minutes: 2) : next,
        () async {
      if (_disposed) return;
      if (_foreground && !_polling) {
        _polling = true;
        try {
          await Future.wait([refreshActiveOrders(), refreshBookingRequests()]);
          final failed =
              activeOrders.error != null || bookingRequests.error != null;
          _failures = failed ? _failures + 1 : 0;
        } finally {
          _polling = false;
        }
      }
      if (!_disposed) _schedule(base);
    });
  }

  /// App moved to background/foreground; polling never runs in the background.
  void setForeground(bool value) {
    final resumed = value && !_foreground;
    _foreground = value;
    if (resumed && !_disposed) {
      _failures = 0;
      unawaited(Future.wait([refreshActiveOrders(), refreshBookingRequests()]));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    newWork.dispose();
    super.dispose();
  }
}
