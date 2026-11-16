import 'partner_api.dart';

/// Existing server contracts; no new backend routes are introduced.
class PartnerOperations {
  const PartnerOperations(this.api, this.partnerId);
  final PartnerApi api;
  final String partnerId;

  String get _root => 'partner/partners/${Uri.encodeComponent(partnerId)}';

  Future<Map<String, dynamic>> activeOrders() =>
      api.get('$_root/food/orders?scope=active');
  Future<Map<String, dynamic>> orderHistory() =>
      api.get('$_root/food/orders?scope=history');
  Future<Map<String, dynamic>> updateOrder(
    String orderId,
    String status, {
    String? reason,
  }) =>
      api.post('$_root/food/orders/${Uri.encodeComponent(orderId)}/status', {
        'status': status,
        if (reason != null) 'reason': reason,
      });

  Future<Map<String, dynamic>> bookingRequests() =>
      api.get('$_root/booking/bookings?scope=requests');
  Future<Map<String, dynamic>> upcomingBookings() =>
      api.get('$_root/booking/bookings?scope=upcoming');
  Future<Map<String, dynamic>> bookingAction(
    String bookingId,
    String action, {
    String? reason,
  }) =>
      api.post('$_root/booking/bookings/${Uri.encodeComponent(bookingId)}/action', {
        'action': action,
        if (reason != null) 'reason': reason,
      });

  Future<Map<String, dynamic>> restaurants() =>
      api.get('$_root/food/restaurants');
  Future<Map<String, dynamic>> venues() =>
      api.get('$_root/booking/venues');
}
