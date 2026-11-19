import '../identity/auth_repository.dart';
import '../rides/ride_api.dart';

class DeliveryApi {
  const DeliveryApi(this.auth);

  final AuthRepository auth;

  Future<List<RideAddress>> addresses() async {
    final data = await auth.addresses();
    return [
      for (final item in data)
        if (item['formattedAddress'] case final String address)
          if (address.length <= 240 &&
              item['latitude'] is num &&
              item['longitude'] is num)
            RideAddress(address, {
              'latitude': item['latitude'],
              'longitude': item['longitude'],
            }),
    ];
  }

  Future<DeliveryQuote> quote(RideAddress pickup, RideAddress destination,
      String type, List<int> measures) async {
    final data = await auth.authorizedJson(
      'POST',
      'deliveries/quotes',
      body: {
        'pickup': pickup.point,
        'destination': destination.point,
        'parcelType': type,
        'weightGrams': measures[0],
        'lengthCm': measures[1],
        'widthCm': measures[2],
        'heightCm': measures[3],
      },
      expected: {201},
    ) as Map<String, dynamic>;
    return DeliveryQuote(
      data['id'] as String,
      data['amountKzt'] as num,
      data['distanceMeters'] as int,
      data['durationSeconds'] as int,
      data['syntheticRoute'] == true,
    );
  }

  Future<DeliveryOrder> create(
      Map<String, dynamic> draft, String idempotencyKey) async {
    return DeliveryOrder.fromJson(await auth.authorizedJson(
      'POST',
      'deliveries',
      body: draft,
      headers: {'Idempotency-Key': idempotencyKey},
      expected: {200, 201},
    ) as Map<String, dynamic>);
  }

  Future<List<DeliveryOrder>> history() async {
    final data =
        await auth.authorizedJson('GET', 'deliveries') as List<dynamic>;
    return [
      for (final item in data)
        DeliveryOrder.fromJson(item as Map<String, dynamic>),
    ];
  }

  Future<DeliveryOrder> detail(String id) => _order('GET', 'deliveries/$id');
  Future<DeliveryOrder> dispatch(String id) =>
      _order('POST', 'deliveries/$id/dispatch');
  Future<DeliveryOrder> cancel(String id) =>
      _order('POST', 'deliveries/$id/cancel');

  Future<DeliveryOrder> rate(String id, int stars) async =>
      DeliveryOrder.fromJson(
        await auth.authorizedJson('POST', 'deliveries/$id/rating',
            body: {'stars': stars}) as Map<String, dynamic>,
      );

  Future<DeliveryOrder> _order(String method, String path) async =>
      DeliveryOrder.fromJson(
        await auth.authorizedJson(method, path) as Map<String, dynamic>,
      );

  Future<(double, double)?> location(String id) async {
    final result = await auth.authorizedJson(
      'GET',
      'deliveries/$id/location',
      expected: {200, 204},
    ) as Map<String, dynamic>?;
    if (result == null) return null;
    return (
      (result['latitude'] as num).toDouble(),
      (result['longitude'] as num).toDouble()
    );
  }

  Future<(String, DateTime)> handoffCode(String id) async {
    final data = await auth.authorizedJson(
            'POST', 'deliveries/$id/handoff-code', expected: {201})
        as Map<String, dynamic>;
    return (
      data['code'] as String,
      DateTime.parse(data['expiresAt'] as String)
    );
  }
}

class DeliveryQuote {
  const DeliveryQuote(
      this.id, this.amount, this.distance, this.duration, this.synthetic);

  final String id;
  final num amount;
  final int distance;
  final int duration;
  final bool synthetic;
}

class DeliveryOrder {
  DeliveryOrder.fromJson(Map<String, dynamic> data)
      : id = data['id'] as String,
        status = data['status'] as String,
        pickup = data['pickupAddress'] as String,
        destination = data['destinationAddress'] as String,
        amount = data['amountKzt'] as num,
        synthetic = data['syntheticRoute'] == true,
        courier =
            (data['courier'] as Map<String, dynamic>?)?['name'] as String?,
        stars = data['stars'] as int?,
        parcel = data['parcel'] as Map<String, dynamic>?,
        pickupPoint = data['pickupPoint'] as Map<String, dynamic>?,
        destinationPoint = data['destinationPoint'] as Map<String, dynamic>?,
        parcelType = data['parcelType'] as String?,
        recipientName = data['recipientName'] as String?,
        recipientPhone = data['recipientPhone'] as String?,
        description = data['description'] as String?,
        courierNote = data['courierNote'] as String?;

  final String id;
  final String status;
  final String pickup;
  final String destination;
  final num amount;
  final bool synthetic;
  final String? courier;
  final int? stars;
  final Map<String, dynamic>? parcel;
  final Map<String, dynamic>? pickupPoint;
  final Map<String, dynamic>? destinationPoint;
  final String? parcelType;
  final String? recipientName;
  final String? recipientPhone;
  final String? description;
  final String? courierNote;

  bool get repeatable =>
      parcel != null && pickupPoint != null && destinationPoint != null;

  bool get active => const {
        'CREATED',
        'SEARCHING_COURIER',
        'COURIER_ASSIGNED',
        'COURIER_ARRIVING',
        'COURIER_ARRIVED',
        'PICKED_UP',
        'IN_TRANSIT',
        'DELIVERED',
        'DELIVERY_FAILED',
        'RETURN_REQUESTED',
        'RETURNING',
      }.contains(status);

  bool get searching => status == 'CREATED' || status == 'SEARCHING_COURIER';

  bool get cancellable =>
      searching ||
      const {'COURIER_ASSIGNED', 'COURIER_ARRIVING', 'COURIER_ARRIVED'}
          .contains(status);
}
