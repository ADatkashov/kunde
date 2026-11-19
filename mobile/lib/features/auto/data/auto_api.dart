import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../../identity/auth_repository.dart';
import 'auto_models.dart';

enum AutoFailure {
  offline,
  sessionExpired,
  slotTaken,
  quoteExpired,
  vehicleBooked,
  tooManyBookings,
  tooManyVehicles,
  notCancellable,
  notReschedulable,
  rescheduleLimit,
  unavailable,
  versionConflict,
  alreadyDone,
  invalid,
  notFound,
  other
}

class AutoException implements Exception {
  const AutoException(this.failure);

  final AutoFailure failure;

  @override
  String toString() => 'AutoException($failure)';
}

/// KUNDE Auto client: public catalog over plain HTTP, vehicles and bookings through the authenticated repository.
/// Prices are never sent: the server computes them in a quote and the booking only references the quote.
class AutoApi {
  AutoApi({
    required Uri baseUri,
    required this.auth,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  })  : _base = baseUri.toString().endsWith('/')
            ? baseUri
            : baseUri.replace(path: '${baseUri.path}/'),
        _client = client ?? http.Client();

  final Uri _base;
  final http.Client _client;
  final AuthRepository auth;
  final Duration timeout;

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on AutoException {
      rethrow;
    } on SessionExpired {
      throw const AutoException(AutoFailure.sessionExpired);
    } on IdentityApiError catch (error) {
      throw AutoException(_map(error));
    } on TimeoutException {
      throw const AutoException(AutoFailure.offline);
    } on IdentityUnavailable {
      throw const AutoException(AutoFailure.offline);
    } on http.ClientException {
      throw const AutoException(AutoFailure.offline);
    } on FormatException {
      throw const AutoException(AutoFailure.other);
    } on TypeError {
      throw const AutoException(AutoFailure.other);
    }
  }

  static AutoFailure _map(IdentityApiError error) => switch (error.code) {
        'SLOT_TAKEN' || 'SLOT_UNAVAILABLE' => AutoFailure.slotTaken,
        'QUOTE_EXPIRED' ||
        'QUOTE_STALE' ||
        'QUOTE_USED' =>
          AutoFailure.quoteExpired,
        'VEHICLE_ALREADY_BOOKED' => AutoFailure.vehicleBooked,
        'TOO_MANY_UPCOMING_BOOKINGS' => AutoFailure.tooManyBookings,
        'TOO_MANY_VEHICLES' => AutoFailure.tooManyVehicles,
        'BOOKING_NOT_CANCELLABLE' => AutoFailure.notCancellable,
        'BOOKING_NOT_RESCHEDULABLE' => AutoFailure.notReschedulable,
        'RESCHEDULE_LIMIT' => AutoFailure.rescheduleLimit,
        'AUTO_DISABLED' || 'AUTO_CATEGORY_DISABLED' => AutoFailure.unavailable,
        'VEHICLE_VERSION_CONFLICT' => AutoFailure.versionConflict,
        'REVIEW_EXISTS' || 'COMPLAINT_ALREADY_OPEN' => AutoFailure.alreadyDone,
        'REVIEW_NOT_ALLOWED' => AutoFailure.notReschedulable,
        'VEHICLE_INVALID' ||
        'VEHICLE_YEAR_INVALID' ||
        'PLATE_INVALID' =>
          AutoFailure.invalid,
        'BOOKING_NOT_FOUND' ||
        'VENUE_NOT_FOUND' ||
        'SERVICE_NOT_FOUND' ||
        'VEHICLE_NOT_FOUND' ||
        'QUOTE_NOT_FOUND' =>
          AutoFailure.notFound,
        _ => error.status == 404 ? AutoFailure.notFound : AutoFailure.other,
      };

  Future<dynamic> _public(String path, [Map<String, String>? query]) =>
      _guard(() async {
        final uri = _base.resolve(path).replace(queryParameters: query);
        final response = await _client
            .get(uri, headers: {'Accept': 'application/json'}).timeout(timeout);
        if (response.statusCode == 404) {
          throw const AutoException(AutoFailure.notFound);
        }
        if (response.statusCode != 200) {
          throw const AutoException(AutoFailure.other);
        }
        return jsonDecode(utf8.decode(response.bodyBytes));
      });

  Future<List<AutoCategory>> categories() async =>
      ((await _public('auto/categories')) as List<dynamic>)
          .map((e) => AutoCategory.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);

  Future<List<AutoVenue>> venues({String? category, String? query}) async =>
      ((await _public('auto/venues', {
        if (category != null) 'category': category,
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      })) as List<dynamic>)
          .map((e) => AutoVenue.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);

  Future<AutoVenueDetail> venue(String id) async => AutoVenueDetail.fromJson(
      (await _public('auto/venues/$id')) as Map<String, dynamic>);

  Future<List<AutoSlot>> slots(
      {required String venueId,
      required String serviceId,
      required DateTime date}) async {
    String two(int v) => v.toString().padLeft(2, '0');
    return ((await _public('auto/slots', {
      'venueId': venueId,
      'serviceId': serviceId,
      'date':
          '${date.year.toString().padLeft(4, '0')}-${two(date.month)}-${two(date.day)}',
    })) as List<dynamic>)
        .map((e) => AutoSlot.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<List<Vehicle>> vehicles() => _guard(() async =>
      ((await auth.authorizedJson('GET', 'auto/vehicles')) as List<dynamic>)
          .map((e) => Vehicle.fromJson(e as Map<String, dynamic>))
          .toList(growable: false));

  Future<Vehicle> saveVehicle(
          {String? id,
          int? version,
          required String make,
          required String model,
          required int year,
          String? plate}) =>
      _guard(() async {
        final body = {
          'make': make.trim(),
          'model': model.trim(),
          'year': year,
          if (plate != null && plate.trim().isNotEmpty) 'plate': plate.trim(),
          if (id != null) 'version': version,
        };
        final json = id == null
            ? await auth.authorizedJson('POST', 'auto/vehicles',
                body: body, expected: const {201})
            : await auth.authorizedJson('PUT', 'auto/vehicles/$id', body: body);
        return Vehicle.fromJson(json as Map<String, dynamic>);
      });

  Future<void> deleteVehicle(String id) => _guard(() async {
        await auth.authorizedJson('DELETE', 'auto/vehicles/$id',
            expected: const {204});
      });

  Future<AutoQuote> quote(
          {required String venueId,
          required String serviceId,
          required String vehicleId,
          required String startsAtIso}) =>
      _guard(() async => AutoQuote.fromJson(
              (await auth.authorizedJson('POST', 'auto/quotes', body: {
            'venueId': venueId,
            'serviceId': serviceId,
            'vehicleId': vehicleId,
            'startsAt': startsAtIso,
          }, expected: const {
            201
          })) as Map<String, dynamic>));

  /// The idempotency key is created once per booking attempt so a retry after a lost response never books twice.
  Future<AutoBookingRecord> book(
          {required String quoteId, required String idempotencyKey}) =>
      _guard(() async => AutoBookingRecord.fromJson((await auth.authorizedJson(
              'POST', 'auto/bookings',
              body: {'quoteId': quoteId},
              expected: const {200, 201},
              headers: {'Idempotency-Key': idempotencyKey}))
          as Map<String, dynamic>));

  Future<List<AutoBookingRecord>> bookings() => _guard(() async =>
      ((await auth.authorizedJson('GET', 'auto/bookings')) as List<dynamic>)
          .map((e) => AutoBookingRecord.fromJson(e as Map<String, dynamic>))
          .toList(growable: false));

  Future<AutoBookingRecord> booking(String id) =>
      _guard(() async => AutoBookingRecord.fromJson((await auth.authorizedJson(
          'GET', 'auto/bookings/$id')) as Map<String, dynamic>));

  Future<AutoBookingRecord> cancel(String id) =>
      _guard(() async => AutoBookingRecord.fromJson((await auth.authorizedJson(
          'POST', 'auto/bookings/$id/cancel')) as Map<String, dynamic>));

  Future<AutoBookingRecord> reschedule(String id, String startsAtIso) =>
      _guard(() async => AutoBookingRecord.fromJson((await auth.authorizedJson(
          'POST', 'auto/bookings/$id/reschedule',
          body: {'startsAt': startsAtIso})) as Map<String, dynamic>));

  Future<AutoBookingRecord> decidePrice(String id, {required bool approve}) =>
      _guard(() async => AutoBookingRecord.fromJson((await auth.authorizedJson(
          'POST', 'auto/bookings/$id/price-decision',
          body: {'approve': approve})) as Map<String, dynamic>));

  /// One review per completed booking; the server refuses a second one.
  Future<void> review(String bookingId,
          {required int rating, String text = ''}) =>
      _guard(() async {
        await auth.authorizedJson('POST', 'auto/bookings/$bookingId/review',
            body: {
              'rating': rating,
              if (text.trim().isNotEmpty) 'text': text.trim()
            },
            expected: const {
              201
            });
      });

  /// [kind]: QUALITY, PRICE, BEHAVIOR, NO_SHOW or OTHER. Only one open complaint per booking.
  Future<void> complain(String bookingId,
          {required String kind, required String description}) =>
      _guard(() async {
        await auth.authorizedJson('POST', 'auto/complaints', body: {
          'bookingId': bookingId,
          'kind': kind,
          'description': description.trim()
        }, expected: const {
          201
        });
      });

  static String newIdempotencyKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return 'au-${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  }

  void close() => _client.close();
}
