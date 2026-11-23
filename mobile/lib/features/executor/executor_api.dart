import 'package:kunde_maps_sdk/kunde_maps_sdk.dart';

import '../identity/auth_repository.dart';

class ExecutorApi {
  const ExecutorApi(this.auth);

  final AuthRepository auth;

  Future<ExecutorProfile?> profile() async {
    try {
      return ExecutorProfile(await _object('GET', 'profile'));
    } on IdentityApiError catch (error) {
      if (error.code == 'DRIVER_NOT_FOUND') return null;
      rethrow;
    }
  }

  Future<void> register(String name) =>
      _object('POST', 'profile', {'displayName': name});

  Future<void> vehicle(String description, String plate, String rideClass) =>
      _object('POST', 'vehicle', {
        'description': description,
        'plate': plate,
        'rideClass': rideClass,
      });

  Future<void> online(bool online) =>
      _object('PUT', 'availability', {'online': online});

  Future<void> location(double latitude, double longitude) => _command(
      'PUT', 'location', {'latitude': latitude, 'longitude': longitude});

  Future<void> respond(String offer, bool accepted) =>
      _command('POST', 'offers/$offer/response', {'accept': accepted});

  Future<void> advance(String trip, String step) =>
      _command('POST', 'trips/$trip/progress', {'step': step});

  Future<List<ExecutorOffer>> offers() async =>
      (await _list('offers')).map(ExecutorOffer.new).toList(growable: false);

  Future<List<ExecutorTrip>> trips() async =>
      (await _list('trips')).map(ExecutorTrip.new).toList(growable: false);

  Future<Map<String, dynamic>> _object(String method, String path,
          [Map<String, dynamic>? body]) async =>
      await auth.authorizedJson(method, 'executor/rides/$path', body: body)
          as Map<String, dynamic>;

  Future<List<Map<String, dynamic>>> _list(String path) async =>
      (await auth.authorizedJson('GET', 'executor/rides/$path')
              as List<dynamic>)
          .cast<Map<String, dynamic>>();

  Future<void> _command(
      String method, String path, Map<String, dynamic> body) async {
    await auth.authorizedJson(method, 'executor/rides/$path',
        body: body, expected: {204});
  }
}

class ExecutorProfile {
  ExecutorProfile(Map<String, dynamic> json)
      : name = json['displayName'] as String,
        status = json['status'] as String,
        online = json['online'] as bool,
        vehicle = json['vehicle'] as Map<String, dynamic>?,
        rating = json['rating'] as num?,
        ratings = (json['ratings'] as num?)?.toInt() ?? 0;

  final String name;
  final String status;
  final bool online;
  final Map<String, dynamic>? vehicle;

  /// Average customer rating; null until the first rating, never estimated.
  final num? rating;
  final int ratings;

  bool get approved => status == 'APPROVED' && vehicle?['status'] == 'APPROVED';
}

class ExecutorOffer {
  ExecutorOffer(Map<String, dynamic> json)
      : id = json['id'] as String,
        expiresAt = DateTime.parse(json['expiresAt'] as String),
        synthetic = json['synthetic'] == true;

  final String id;
  final DateTime expiresAt;
  final bool synthetic;
}

class ExecutorTrip {
  ExecutorTrip(Map<String, dynamic> json)
      : id = json['id'] as String,
        status = json['status'] as String,
        createdAt = DateTime.parse(json['createdAt'] as String),
        synthetic = json['synthetic'] == true,
        pickup = _point(json['pickup']),
        destination = _point(json['destination']),
        fareKzt = json['fareKzt'] as num?,
        completedAt = json['completedAt'] == null
            ? null
            : DateTime.parse(json['completedAt'] as String);

  final String id;
  final String status;
  final DateTime createdAt;
  final bool synthetic;

  /// Quoted tariff fare in KZT. It is an estimate, not a captured payment.
  final num? fareKzt;
  final DateTime? completedAt;

  /// Route endpoints, sent by the server to the assigned driver while the trip is active only.
  final GeoPoint? pickup;
  final GeoPoint? destination;

  static GeoPoint? _point(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    try {
      return GeoPoint.parse(value['latitude'], value['longitude']);
    } on FormatException {
      return null;
    }
  }

  /// Where the driver should be guided now: to the passenger until the ride
  /// starts, then to the destination. At the pickup point there is nothing to
  /// navigate.
  GeoPoint? get navigationTarget => switch (status) {
        'DRIVER_ASSIGNED' || 'DRIVER_ARRIVING' => pickup,
        'IN_PROGRESS' => destination,
        _ => null,
      };

  String? get nextStep => switch (status) {
        'DRIVER_ASSIGNED' => 'DEPART',
        'DRIVER_ARRIVING' => 'ARRIVE',
        'DRIVER_ARRIVED' => 'START',
        'IN_PROGRESS' => 'COMPLETE',
        _ => null,
      };
}
