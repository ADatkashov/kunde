import 'models.dart';
import 'partner_api.dart';

/// Existing server contracts only; no new backend routes are introduced.
/// All state transitions are decided by the backend (`allowedNext`,
/// `allowedActions`); this class never invents one.
class PartnerOperations {
  const PartnerOperations(this.api, this.partnerId);
  final PartnerApi api;
  final String partnerId;

  String get _root => 'partner/partners/${Uri.encodeComponent(partnerId)}';

  // ── Food orders ───────────────────────────────────────────────────
  Future<List<PartnerOrder>> orders(
      {required bool history, int limit = 30, int offset = 0}) async {
    final scope = history ? 'history' : 'active';
    final rows = await api
        .getList('$_root/food/orders?scope=$scope&limit=$limit&offset=$offset');
    return rows.map(PartnerOrder.fromJson).toList();
  }

  Future<PartnerOrder> updateOrder(String orderId, String status,
      {String? reason}) async {
    final json = await api
        .postMap('$_root/food/orders/${Uri.encodeComponent(orderId)}/status', {
      'status': status,
      if (reason != null) 'reason': reason,
    });
    return PartnerOrder.fromJson(json);
  }

  // ── Bookings ──────────────────────────────────────────────────────
  Future<List<PartnerBooking>> bookings(
      {required String scope, int limit = 30, int offset = 0}) async {
    final rows = await api.getList(
        '$_root/booking/bookings?scope=$scope&limit=$limit&offset=$offset');
    return rows.map(PartnerBooking.fromJson).toList();
  }

  Future<PartnerBooking> bookingAction(String bookingId, String action,
      {String? reason}) async {
    final json = await api.postMap(
        '$_root/booking/bookings/${Uri.encodeComponent(bookingId)}/action', {
      'action': action,
      if (reason != null) 'reason': reason,
    });
    return PartnerBooking.fromJson(json);
  }

  // ── Catalog ───────────────────────────────────────────────────────
  Future<List<Restaurant>> restaurants() async =>
      (await api.getList('$_root/food/restaurants'))
          .map(Restaurant.fromJson)
          .toList();

  Future<List<Venue>> venues() async =>
      (await api.getList('$_root/booking/venues')).map(Venue.fromJson).toList();
}
