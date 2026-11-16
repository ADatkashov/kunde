import '../identity/auth_repository.dart';

/// Partner operations client (orders, bookings, availability). Every call goes through the authenticated repository
/// (same token handling and 401 behavior as the rest of the app); the server decides what the caller may see or change.
class PartnerOpsApi {
  PartnerOpsApi(this.auth, String partnerId)
      : _base = 'partner/partners/${_uuid(partnerId)}';

  final AuthRepository auth;
  final String _base;

  static final _uuidPattern = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

  static String _uuid(String value) {
    if (!_uuidPattern.hasMatch(value)) {
      throw ArgumentError.value(value, 'id', 'Invalid ID');
    }
    return value;
  }

  Future<List<Map<String, dynamic>>> _list(String path) async {
    final result = await auth.authorizedJson('GET', '$_base/$path');
    return (result as List<dynamic>)
        .map((entry) => entry as Map<String, dynamic>)
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> _send(
          String method, String path, Map<String, dynamic> body) async =>
      (await auth.authorizedJson(method, '$_base/$path', body: body))
          as Map<String, dynamic>;

  // ---- Food / Grocery orders ----

  /// `scope`: `active` (needs action or in progress) or `history`.
  Future<List<Map<String, dynamic>>> foodOrders(String scope) =>
      _list('food/orders?scope=$scope&limit=50');

  Future<Map<String, dynamic>> setFoodOrderStatus(String orderId, String status,
          {String? reason}) =>
      _send('POST', 'food/orders/${_uuid(orderId)}/status',
          {'status': status, if (reason != null) 'reason': reason});

  Future<List<Map<String, dynamic>>> restaurants() => _list('food/restaurants');

  Future<Map<String, dynamic>> setRestaurantOpen(String id, bool open) =>
      _send('PATCH', 'food/restaurants/${_uuid(id)}', {'open': open});

  Future<List<Map<String, dynamic>>> dishes(String restaurantId) =>
      _list('food/restaurants/${_uuid(restaurantId)}/dishes');

  /// Availability/stock are open to every staff role; [name], [description] and [priceMinor] need Owner/Manager.
  Future<Map<String, dynamic>> updateDish(String restaurantId, String dishId,
          {bool? available,
          int? stockQty,
          bool clearStock = false,
          String? name,
          String? description,
          int? priceMinor}) =>
      _send('PATCH',
          'food/restaurants/${_uuid(restaurantId)}/dishes/${_uuid(dishId)}', {
        if (available != null) 'available': available,
        if (stockQty != null) 'stockQty': stockQty,
        if (clearStock) 'clearStock': true,
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (priceMinor != null) 'priceMinor': priceMinor,
      });

  Future<Map<String, dynamic>> createDish(String restaurantId,
          {required String sectionId,
          required String name,
          String? description,
          required int priceMinor}) async =>
      (await auth.authorizedJson(
          'POST', '$_base/food/restaurants/${_uuid(restaurantId)}/dishes',
          body: {
            'sectionId': _uuid(sectionId),
            'name': name,
            if (description != null && description.isNotEmpty)
              'description': description,
            'priceMinor': priceMinor,
          },
          expected: {
            201
          })) as Map<String, dynamic>;

  // ---- Bookings ----

  /// `scope`: `requests`, `upcoming` or `history`.
  Future<List<Map<String, dynamic>>> bookings(String scope) =>
      _list('booking/bookings?scope=$scope&limit=50');

  Future<Map<String, dynamic>> bookingAction(String bookingId, String action,
          {String? reason}) =>
      _send('POST', 'booking/bookings/${_uuid(bookingId)}/action',
          {'action': action, if (reason != null) 'reason': reason});

  Future<List<Map<String, dynamic>>> venues() => _list('booking/venues');

  Future<Map<String, dynamic>> setVenueOpen(String id, bool open) =>
      _send('PATCH', 'booking/venues/${_uuid(id)}', {'open': open});

  Future<List<Map<String, dynamic>>> services(String venueId) =>
      _list('booking/venues/${_uuid(venueId)}/services');

  Future<Map<String, dynamic>> setServiceAvailable(
          String venueId, String serviceId, bool available) =>
      _send(
          'PATCH',
          'booking/venues/${_uuid(venueId)}/services/${_uuid(serviceId)}',
          {'available': available});

  Future<List<Map<String, dynamic>>> masters(String venueId) =>
      _list('booking/venues/${_uuid(venueId)}/masters');

  Future<Map<String, dynamic>> setMasterActive(
          String venueId, String masterId, bool active) =>
      _send(
          'PATCH',
          'booking/venues/${_uuid(venueId)}/masters/${_uuid(masterId)}',
          {'active': active});

  /// Replaces the weekly schedule; a weekday that is not listed is a day off.
  Future<Map<String, dynamic>> setMasterHours(
          String venueId, String masterId, List<Map<String, dynamic>> hours) =>
      _send(
          'PUT',
          'booking/venues/${_uuid(venueId)}/masters/${_uuid(masterId)}/hours',
          {'hours': hours});
}
