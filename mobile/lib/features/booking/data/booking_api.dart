import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../../identity/auth_repository.dart';
import 'booking_models.dart';

enum BookingFailure {
  offline,
  sessionExpired,
  slotTaken,
  overlaps,
  tooMany,
  notCancellable,
  notFound,
  addressRequired,
  areaInvalid,
  other
}

class BookingException implements Exception {
  const BookingException(this.failure);

  final BookingFailure failure;

  /// Russian default text; screens use `KundeLocalizations.bkError(failure)` for the user's language.
  String get message => switch (failure) {
        BookingFailure.offline =>
          'Нет связи с сервером. Проверьте интернет и попробуйте снова.',
        BookingFailure.sessionExpired => 'Сессия истекла. Войдите снова.',
        BookingFailure.slotTaken =>
          'Это время только что заняли. Выберите другое.',
        BookingFailure.overlaps => 'У вас уже есть запись на это время.',
        BookingFailure.tooMany =>
          'Слишком много предстоящих записей. Отмените одну из них.',
        BookingFailure.notCancellable =>
          'Запись уже нельзя отменить: услуга началась или запись отменена.',
        BookingFailure.notFound => 'Не найдено.',
        BookingFailure.addressRequired => 'Укажите адрес, где нужна услуга.',
        BookingFailure.areaInvalid =>
          'Площадь вне допустимого диапазона для этой услуги.',
        BookingFailure.other =>
          'Не удалось выполнить действие. Попробуйте позже.',
      };
}

/// KUNDE booking client: public catalog over plain HTTP, bookings through the authenticated repository.
class BookingApi {
  BookingApi({
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
    } on BookingException {
      rethrow;
    } on SessionExpired {
      throw const BookingException(BookingFailure.sessionExpired);
    } on IdentityApiError catch (error) {
      throw BookingException(_map(error));
    } on TimeoutException {
      throw const BookingException(BookingFailure.offline);
    } on IdentityUnavailable {
      throw const BookingException(BookingFailure.offline);
    } on http.ClientException {
      throw const BookingException(BookingFailure.offline);
    } on FormatException {
      throw const BookingException(BookingFailure.other);
    } on TypeError {
      throw const BookingException(BookingFailure.other);
    }
  }

  static BookingFailure _map(IdentityApiError error) => switch (error.code) {
        'SLOT_TAKEN' || 'SLOT_UNAVAILABLE' => BookingFailure.slotTaken,
        'BOOKING_OVERLAPS_YOURS' => BookingFailure.overlaps,
        'TOO_MANY_UPCOMING_BOOKINGS' => BookingFailure.tooMany,
        'BOOKING_NOT_CANCELLABLE' => BookingFailure.notCancellable,
        'ADDRESS_REQUIRED' => BookingFailure.addressRequired,
        'AREA_INVALID' || 'AREA_NOT_APPLICABLE' => BookingFailure.areaInvalid,
        'BOOKING_NOT_FOUND' ||
        'VENUE_NOT_FOUND' ||
        'SERVICE_NOT_FOUND' ||
        'MASTER_NOT_FOUND' =>
          BookingFailure.notFound,
        _ =>
          error.status == 404 ? BookingFailure.notFound : BookingFailure.other,
      };

  Future<dynamic> _public(String path, [Map<String, String>? query]) =>
      _guard(() async {
        final uri = _base.resolve(path).replace(queryParameters: query);
        final response = await _client
            .get(uri, headers: {'Accept': 'application/json'}).timeout(timeout);
        if (response.statusCode == 404) {
          throw const BookingException(BookingFailure.notFound);
        }
        if (response.statusCode != 200) {
          throw const BookingException(BookingFailure.other);
        }
        return jsonDecode(utf8.decode(response.bodyBytes));
      });

  /// [category] is `BARBER` (Beauty → barbershops) or `CLEANING` (Home services → cleaning).
  Future<List<BookingVenue>> venues({String category = 'BARBER'}) async =>
      ((await _public('booking/venues', {'category': category}))
              as List<dynamic>)
          .map((e) => BookingVenue.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);

  Future<List<BookingVenue>> healthVenues({
    required String query,
    required String direction,
    required int limit,
    required int offset,
  }) async =>
      ((await _public('booking/health/venues', {
        'q': query,
        'direction': direction,
        'limit': '$limit',
        'offset': '$offset',
      })) as List<dynamic>)
          .map((item) => BookingVenue.fromJson(item as Map<String, dynamic>))
          .toList(growable: false);

  Future<VenueDetail> venue(String id) async => VenueDetail.fromJson(
      (await _public('booking/venues/$id')) as Map<String, dynamic>);

  /// Free start times on [date] for one master, or for any master when [masterId] is null.
  Future<List<BookingSlot>> slots({
    required String venueId,
    required String serviceId,
    String? masterId,
    required DateTime date,
  }) async {
    final day =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return ((await _public('booking/slots', {
      'venueId': venueId,
      'serviceId': serviceId,
      if (masterId != null) 'masterId': masterId,
      'date': day,
    })) as List<dynamic>)
        .map((e) => BookingSlot.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// The idempotency key is generated once per booking attempt so a retry never creates a second booking.
  Future<BookingRecord> book({
    required String venueId,
    required String serviceId,
    required String masterId,
    required String startsAtIso,
    String? comment,
    String? addressText,
    int? areaSqm,
    required String idempotencyKey,
    int? expectedPriceMinor,
    String? paymentMethod,
    bool? acceptsTerms,
  }) =>
      _guard(() async {
        final json =
            await auth.authorizedJson('POST', 'booking/bookings', body: {
          'venueId': venueId,
          'serviceId': serviceId,
          'masterId': masterId,
          'startsAt': startsAtIso,
          if (expectedPriceMinor != null)
            'expectedPriceMinor': expectedPriceMinor,
          if (paymentMethod != null) 'paymentMethod': paymentMethod,
          if (acceptsTerms != null) 'acceptsTerms': acceptsTerms,
          if (comment != null && comment.trim().isNotEmpty)
            'comment': comment.trim(),
          if (addressText != null && addressText.trim().isNotEmpty)
            'addressText': addressText.trim(),
          if (areaSqm != null) 'areaSqm': areaSqm,
        }, expected: const {
          200,
          201
        }, headers: {
          'Idempotency-Key': idempotencyKey
        });
        return BookingRecord.fromJson(json as Map<String, dynamic>);
      });

  Future<List<BookingRecord>> bookings({bool healthOnly = false}) =>
      _guard(() async {
        final json = await auth.authorizedJson(
            'GET',
            healthOnly
                ? 'booking/bookings?healthOnly=true&limit=100'
                : 'booking/bookings');
        return (json as List<dynamic>)
            .map((e) => BookingRecord.fromJson(e as Map<String, dynamic>))
            .toList(growable: false);
      });

  Future<BookingRecord> booking(String id) =>
      _guard(() async => BookingRecord.fromJson((await auth.authorizedJson(
          'GET', 'booking/bookings/$id')) as Map<String, dynamic>));

  Future<BookingRecord> cancel(String id) =>
      _guard(() async => BookingRecord.fromJson((await auth.authorizedJson(
          'POST', 'booking/bookings/$id/cancel')) as Map<String, dynamic>));

  Future<BookingRecord> reschedule(BookingRecord booking, BookingSlot slot) =>
      _guard(() async => BookingRecord.fromJson((await auth.authorizedJson(
              'POST', 'booking/bookings/${booking.id}/reschedule',
              body: {
                'startsAt': slot.startsAtIso,
                'expectedStartsAt': booking.startsAtIso,
              })) as Map<String, dynamic>));

  static String newIdempotencyKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return 'bk-${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  }

  void close() => _client.close();
}
