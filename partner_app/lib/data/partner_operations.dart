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

  Future<bool> fleetEnabled() async =>
      (await api.getMap('capabilities'))['ridesFleetEnabled'] == true;

  Future<Map<String, dynamic>> fleet() => api.getMap('$_root/rides/fleet');

  Future<Map<String, dynamic>> applyFleet() =>
      api.postMap('$_root/rides/fleet', {});

  Future<Map<String, dynamic>> assignFleetDriver(String driver, bool attach) =>
      api.putMap('$_root/rides/fleet/drivers/${Uri.encodeComponent(driver)}',
          {'attach': attach});

  Future<Map<String, dynamic>> capabilities() => api.getMap('capabilities');

  Future<List<Map<String, dynamic>>> shipments() =>
      api.getList('$_root/deliveries');

  Future<Map<String, dynamic>> shipment(String id) =>
      api.getMap('$_root/deliveries/${Uri.encodeComponent(id)}');

  Future<List<Map<String, dynamic>>> shipmentTotals() =>
      api.getList('$_root/deliveries/totals');

  Future<Map<String, dynamic>> shipmentQuote(Map<String, dynamic> body) =>
      api.postMap('$_root/deliveries/quotes', body);

  Future<Map<String, dynamic>> createShipment(
    Map<String, dynamic> body,
    String key,
  ) =>
      api.postMap('$_root/deliveries', body, idempotencyKey: key);

  Future<Map<String, dynamic>> shipmentAction(String id, String action) =>
      api.postMap('$_root/deliveries/${Uri.encodeComponent(id)}/$action', {});

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

  // ── Restaurant management ─────────────────────────────────────────
  String _restaurant(String id) =>
      '$_root/food/restaurants/${Uri.encodeComponent(id)}';

  Future<Restaurant> setRestaurantOpen(String id, bool open) async =>
      Restaurant.fromJson(await api.patchMap(_restaurant(id), {'open': open}));

  Future<List<Dish>> dishes(String restaurantId) async =>
      (await api.getList('${_restaurant(restaurantId)}/dishes'))
          .map(Dish.fromJson)
          .toList();

  /// Sends only the fields that changed. Name/description/price need the
  /// Owner or Manager role (the server enforces it).
  Future<Dish> updateDish(
    String restaurantId,
    String dishId, {
    bool? available,
    int? stockQty,
    bool clearStock = false,
    String? name,
    String? description,
    int? priceMinor,
  }) async =>
      Dish.fromJson(await api.patchMap(
        '${_restaurant(restaurantId)}/dishes/${Uri.encodeComponent(dishId)}',
        {
          if (available != null) 'available': available,
          if (stockQty != null) 'stockQty': stockQty,
          if (clearStock) 'clearStock': true,
          if (name != null) 'name': name,
          if (description != null) 'description': description,
          if (priceMinor != null) 'priceMinor': priceMinor,
        },
      ));

  Future<Dish> createDish(
    String restaurantId, {
    required String sectionId,
    required String name,
    String? description,
    required int priceMinor,
  }) async =>
      Dish.fromJson(await api.postMap('${_restaurant(restaurantId)}/dishes', {
        'sectionId': sectionId,
        'name': name,
        if (description != null && description.isNotEmpty)
          'description': description,
        'priceMinor': priceMinor,
      }));

  // ── Venue (booking) management ────────────────────────────────────
  String _venue(String id) =>
      '$_root/booking/venues/${Uri.encodeComponent(id)}';

  Future<Venue> setVenueOpen(String id, bool open) async =>
      Venue.fromJson(await api.patchMap(_venue(id), {'open': open}));

  Future<List<VenueService>> services(String venueId) async =>
      (await api.getList('${_venue(venueId)}/services'))
          .map(VenueService.fromJson)
          .toList();

  Future<VenueService> setServiceAvailable(
          String venueId, String serviceId, bool available) async =>
      VenueService.fromJson(await api.patchMap(
          '${_venue(venueId)}/services/${Uri.encodeComponent(serviceId)}',
          {'available': available}));

  Future<List<Master>> masters(String venueId) async =>
      (await api.getList('${_venue(venueId)}/masters'))
          .map(Master.fromJson)
          .toList();

  Future<Master> setMasterActive(
          String venueId, String masterId, bool active) async =>
      Master.fromJson(await api.patchMap(
          '${_venue(venueId)}/masters/${Uri.encodeComponent(masterId)}',
          {'active': active}));

  /// Replaces the whole weekly schedule; a missing weekday is a day off.
  Future<Master> setMasterHours(
          String venueId, String masterId, List<WorkingHours> hours) async =>
      Master.fromJson(await api.putMap(
          '${_venue(venueId)}/masters/${Uri.encodeComponent(masterId)}/hours', {
        'hours': [for (final h in hours) h.toJson()]
      }));
}
