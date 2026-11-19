import '../identity/auth_repository.dart';

class RideApi {
  const RideApi(this.auth);

  final AuthRepository auth;

  Future<List<RideAddress>> search(String query, String language) async {
    final result = await auth.authorizedJson(
      'POST',
      'rides/address-search',
      body: {'query': query, 'language': language},
    ) as List<dynamic>;
    return result
        .map((item) => RideAddress.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<RideQuote> quote(
    RideAddress pickup,
    RideAddress destination,
    String rideClass,
  ) async {
    final data = await auth.authorizedJson(
      'POST',
      'rides/quotes',
      body: {
        'pickup': pickup.point,
        'destination': destination.point,
        'rideClass': rideClass,
      },
      expected: {201},
    ) as Map<String, dynamic>;
    return RideQuote(
      data['id'] as String,
      data['estimateKzt'] as num,
      data['distanceMeters'] as int,
      data['durationSeconds'] as int,
      data['synthetic'] == true,
    );
  }

  Future<RideTrip> create(RideQuote quote, String key) async {
    final data = await auth.authorizedJson(
      'POST',
      'rides',
      body: {'quoteId': quote.id},
      headers: {'Idempotency-Key': key},
      expected: {200, 201},
    ) as Map<String, dynamic>;
    return RideTrip.fromJson(data);
  }

  Future<List<RideTrip>> history() async {
    final result = await auth.authorizedJson('GET', 'rides') as List<dynamic>;
    return result
        .map((item) => RideTrip.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<RideTrip> detail(String id) async => RideTrip.fromJson(
        await auth.authorizedJson('GET', 'rides/$id') as Map<String, dynamic>,
      );

  Future<RideTrip> dispatch(String id) async => RideTrip.fromJson(
        await auth.authorizedJson('POST', 'rides/$id/dispatch')
            as Map<String, dynamic>,
      );

  Future<RideDriverLocation?> driverLocation(String id) async {
    final result = await auth.authorizedJson(
      'GET',
      'rides/$id/location',
      expected: {200, 204},
    ) as Map<String, dynamic>?;
    if (result == null) return null;
    final point = result['point'] as Map<String, dynamic>;
    return RideDriverLocation(
      (point['latitude'] as num).toDouble(),
      (point['longitude'] as num).toDouble(),
    );
  }

  Future<RideTrip> cancel(String id) async => RideTrip.fromJson(
        await auth.authorizedJson('POST', 'rides/$id/cancel')
            as Map<String, dynamic>,
      );
}

class RideAddress {
  const RideAddress(this.label, this.point);

  factory RideAddress.fromJson(Map<String, dynamic> data) => RideAddress(
        data['address'] as String,
        Map<String, dynamic>.unmodifiable(
            data['point'] as Map<String, dynamic>),
      );

  final String label;
  final Map<String, dynamic> point;
}

class RideQuote {
  const RideQuote(
    this.id,
    this.fare,
    this.distanceMeters,
    this.durationSeconds,
    this.synthetic,
  );

  final String id;
  final num fare;
  final int distanceMeters;
  final int durationSeconds;
  final bool synthetic;
}

class RideTrip {
  const RideTrip(
      this.id, this.status, this.fare, this.createdAt, this.synthetic);

  factory RideTrip.fromJson(Map<String, dynamic> data) => RideTrip(
        data['id'] as String,
        data['status'] as String,
        data['estimateKzt'] as num,
        DateTime.parse(data['createdAt'] as String),
        data['synthetic'] == true,
      );

  final String id;
  final String status;
  final num fare;
  final DateTime createdAt;
  final bool synthetic;

  bool get searching => status == 'REQUESTED' || status == 'SEARCHING_DRIVER';

  bool get cancellable =>
      searching ||
      const {
        'DRIVER_ASSIGNED',
        'DRIVER_ARRIVING',
        'DRIVER_ARRIVED',
      }.contains(status);

  bool get active => cancellable || status == 'IN_PROGRESS';
}

class RideDriverLocation {
  const RideDriverLocation(this.latitude, this.longitude);
  final double latitude;
  final double longitude;
}
