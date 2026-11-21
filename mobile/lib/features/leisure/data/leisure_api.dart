import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../../identity/auth_repository.dart';
import 'leisure_models.dart';

/// The two products on the one ticketing engine: Events (dated tickets) and Leisure (bookable activities). They differ only in the
/// public catalogue paths; seats, holds, orders and tickets are shared (`leisure/...`).
enum LeisureProduct { leisure, events }

enum LeisureFailure {
  offline,
  sessionExpired,
  disabled,
  seatTaken,
  notEnoughPlaces,
  holdExpired,
  sessionClosed,
  paymentUnsupported,
  ageRequired,
  guestsLimit,
  tooManyBookings,
  cancellationClosed,
  ticketUsed,
  alreadyDone,
  notAllowed,
  invalid,
  notFound,
  other
}

class LeisureException implements Exception {
  const LeisureException(this.failure);

  final LeisureFailure failure;

  @override
  String toString() => 'LeisureException($failure)';
}

/// Where the global search sends a query: Events (ticketed dated events), Leisure (bookable activities), both, or nowhere.
class SearchRoute {
  const SearchRoute(this.route, this.category);

  factory SearchRoute.fromJson(Map<String, dynamic> json) => SearchRoute(
      json['route'] as String? ?? 'NONE', json['category'] as String?);

  final String route;
  final String? category;
}

class SeatChoice {
  const SeatChoice(this.seatId, this.ticketTypeId);

  final String seatId;
  final String ticketTypeId;
}

/// KUNDE Leisure client. The catalogue is public; holds, orders and tickets go through the authenticated repository. The client never sends a
/// price: the server prices a hold from ticket types and the order only references the hold, so a modified app cannot change what is charged.
class LeisureApi {
  LeisureApi({
    required Uri baseUri,
    required this.auth,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
    this.product = LeisureProduct.leisure,
  })  : _base = baseUri.toString().endsWith('/')
            ? baseUri
            : baseUri.replace(path: '${baseUri.path}/'),
        _client = client ?? http.Client();

  final Uri _base;
  final http.Client _client;
  final AuthRepository auth;
  final Duration timeout;
  final LeisureProduct product;

  /// The same client (connection, session, timeout) reading the catalogue of another product.
  LeisureApi forProduct(LeisureProduct other) => LeisureApi(
        baseUri: _base,
        auth: auth,
        client: _client,
        timeout: timeout,
        product: other,
      );

  bool get _events => product == LeisureProduct.events;
  String get _categoriesPath =>
      _events ? 'events/categories' : 'leisure/categories';
  String get _listPath => _events ? 'events' : 'leisure/events';
  String get _homePath => _events ? 'events/home' : 'leisure/home';
  String _detailPath(String id) =>
      _events ? 'events/$id' : 'leisure/events/$id';

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on LeisureException {
      rethrow;
    } on SessionExpired {
      throw const LeisureException(LeisureFailure.sessionExpired);
    } on IdentityApiError catch (error) {
      throw LeisureException(_map(error));
    } on TimeoutException {
      throw const LeisureException(LeisureFailure.offline);
    } on IdentityUnavailable {
      throw const LeisureException(LeisureFailure.offline);
    } on http.ClientException {
      throw const LeisureException(LeisureFailure.offline);
    } on FormatException {
      throw const LeisureException(LeisureFailure.other);
    } on TypeError {
      throw const LeisureException(LeisureFailure.other);
    }
  }

  static LeisureFailure _map(IdentityApiError error) => switch (error.code) {
        'LEISURE_DISABLED' || 'EVENTS_DISABLED' => LeisureFailure.disabled,
        'SEAT_TAKEN' => LeisureFailure.seatTaken,
        'NOT_ENOUGH_PLACES' => LeisureFailure.notEnoughPlaces,
        'HOLD_EXPIRED' || 'HOLD_NOT_FOUND' => LeisureFailure.holdExpired,
        'SESSION_STARTED' ||
        'SESSION_NOT_AVAILABLE' ||
        'SESSION_NOT_FOUND' =>
          LeisureFailure.sessionClosed,
        'PAYMENT_METHOD_UNSUPPORTED' => LeisureFailure.paymentUnsupported,
        'AGE_CONFIRMATION_REQUIRED' => LeisureFailure.ageRequired,
        'GUESTS_LIMIT' => LeisureFailure.guestsLimit,
        'TOO_MANY_UPCOMING' => LeisureFailure.tooManyBookings,
        'CANCELLATION_WINDOW_CLOSED' => LeisureFailure.cancellationClosed,
        'TICKET_USED' => LeisureFailure.ticketUsed,
        'ALREADY_REVIEWED' => LeisureFailure.alreadyDone,
        'REVIEW_NOT_ALLOWED' => LeisureFailure.notAllowed,
        'SELECTION_INVALID' ||
        'TICKET_TYPE_INVALID' ||
        'SEAT_INVALID' ||
        'SEAT_ZONE_MISMATCH' ||
        'SEATS_REQUIRED' ||
        'RATING_INVALID' ||
        'COMPLAINT_INVALID' =>
          LeisureFailure.invalid,
        'EVENT_NOT_FOUND' || 'ORDER_NOT_FOUND' => LeisureFailure.notFound,
        _ =>
          error.status == 404 ? LeisureFailure.notFound : LeisureFailure.other,
      };

  Future<dynamic> _public(String path, [Map<String, String>? query]) =>
      _guard(() async {
        final uri = _base.resolve(path).replace(queryParameters: query);
        final response = await _client
            .get(uri, headers: {'Accept': 'application/json'}).timeout(timeout);
        if (response.statusCode == 404) {
          throw const LeisureException(LeisureFailure.notFound);
        }
        if (response.statusCode != 200) {
          throw const LeisureException(LeisureFailure.other);
        }
        return jsonDecode(utf8.decode(response.bodyBytes));
      });

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<SearchRoute> route(String query) async =>
      SearchRoute.fromJson((await _public('search/route', {'q': query.trim()}))
          as Map<String, dynamic>);

  Future<List<LeisureCategory>> categories() async =>
      ((await _public(_categoriesPath)) as List<dynamic>)
          .map((e) => LeisureCategory.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);

  Future<List<EventCard>> events(LeisureFilter f,
          {int limit = 30, int offset = 0}) async =>
      ((await _public(_listPath, {
        if (f.query.trim().isNotEmpty) 'q': f.query.trim(),
        if (f.category != null) 'category': f.category!,
        if (f.district != null) 'district': f.district!,
        if (f.date != null) 'date': _date(f.date!),
        if (f.preset != null) 'preset': f.preset!,
        if (f.minPriceMinor != null) 'minPrice': '${f.minPriceMinor}',
        if (f.maxPriceMinor != null) 'maxPrice': '${f.maxPriceMinor}',
        if (f.age != null) 'age': '${f.age}',
        if (f.guests != null) 'guests': '${f.guests}',
        if (f.availableOnly) 'available': 'true',
        if (f.family) 'family': 'true',
        if (f.minRating != null) 'minRating': '${f.minRating}',
        if (f.lat != null && f.lng != null) ...{
          'lat': '${f.lat}',
          'lng': '${f.lng}',
        },
        if (f.radiusKm != null) 'radiusKm': '${f.radiusKm}',
        'sort': f.sort,
        'limit': '$limit',
        'offset': '$offset',
      })) as List<dynamic>)
          .map((e) => EventCard.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);

  /// Home sections (today, weekend, family, popular, near): every card comes from the real catalogue.
  Future<Map<String, List<EventCard>>> home({double? lat, double? lng}) async {
    final json = (await _public(_homePath, {
      if (lat != null && lng != null) ...{'lat': '$lat', 'lng': '$lng'},
    })) as Map<String, dynamic>;
    return {
      for (final e in json.entries)
        e.key: [
          for (final c in e.value as List<dynamic>)
            EventCard.fromJson(c as Map<String, dynamic>)
        ]
    };
  }

  Future<EventDetail> event(String id) async => EventDetail.fromJson(
      (await _public(_detailPath(id))) as Map<String, dynamic>);

  Future<List<SessionInfo>> sessions(String eventId, DateTime from,
          {int days = 14}) async =>
      ((await _public('${_detailPath(eventId)}/sessions',
              {'date': _date(from), 'days': '$days'})) as List<dynamic>)
          .map((e) => SessionInfo.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);

  Future<List<SeatInfo>> seats(String sessionId) async =>
      ((await _public('leisure/sessions/$sessionId/seats')) as List<dynamic>)
          .map((e) => SeatInfo.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);

  Future<List<Review>> reviews(String eventId) async =>
      ((await _public('leisure/events/$eventId/reviews')) as List<dynamic>)
          .map((e) => Review.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);

  // ---- authenticated ---------------------------------------------------------------------------------------------------------

  Future<Hold> holdSeats(String sessionId, List<SeatChoice> seats) =>
      _guard(() async {
        final byType = <String, List<String>>{};
        for (final s in seats) {
          byType.putIfAbsent(s.ticketTypeId, () => []).add(s.seatId);
        }
        return Hold.fromJson(await auth.authorizedJson(
          'POST',
          'leisure/sessions/$sessionId/holds',
          body: {
            'lines': [
              for (final e in byType.entries)
                {
                  'ticketTypeId': e.key,
                  'quantity': e.value.length,
                  'seatIds': e.value
                }
            ],
          },
          expected: {201},
        ) as Map<String, dynamic>);
      });

  /// [quantities] maps a ticket type id to the number of tickets (per-person pricing) or `1` (per-booking pricing).
  Future<Hold> holdTickets(String sessionId, Map<String, int> quantities,
          {int? guests}) =>
      _guard(() async => Hold.fromJson(await auth.authorizedJson(
            'POST',
            'leisure/sessions/$sessionId/holds',
            body: {
              if (guests != null) 'guests': guests,
              'lines': [
                for (final e in quantities.entries)
                  if (e.value > 0) {'ticketTypeId': e.key, 'quantity': e.value}
              ],
            },
            expected: {201},
          ) as Map<String, dynamic>));

  Future<void> release(String holdId) => _guard(() async {
        await auth
            .authorizedJson('DELETE', 'leisure/holds/$holdId', expected: {204});
      });

  /// A fresh key per purchase attempt; the caller keeps it across retries so a repeated request cannot create a second order.
  static String newKey() {
    final r = Random.secure();
    return 'lk-${List.generate(24, (_) => r.nextInt(16).toRadixString(16)).join()}';
  }

  Future<LeisureOrder> place({
    required String holdId,
    required String paymentMethod,
    required bool ageConfirmed,
    required String idempotencyKey,
  }) =>
      _guard(() async => LeisureOrder.fromJson(await auth.authorizedJson(
            'POST',
            'leisure/orders',
            body: {
              'holdId': holdId,
              'paymentMethod': paymentMethod,
              'ageConfirmed': ageConfirmed,
            },
            expected: {200, 201},
            headers: {'Idempotency-Key': idempotencyKey},
          ) as Map<String, dynamic>));

  Future<List<LeisureOrder>> orders(String scope) =>
      _guard(() async => ((await auth.authorizedJson(
              'GET', 'leisure/orders?scope=$scope&limit=50')) as List<dynamic>)
          .map((e) => LeisureOrder.fromJson(e as Map<String, dynamic>))
          .toList(growable: false));

  Future<LeisureOrder> order(String id) =>
      _guard(() async => LeisureOrder.fromJson(await auth.authorizedJson(
          'GET', 'leisure/orders/$id') as Map<String, dynamic>));

  Future<LeisureOrder> cancel(String id) =>
      _guard(() async => LeisureOrder.fromJson(await auth.authorizedJson(
          'POST', 'leisure/orders/$id/cancel') as Map<String, dynamic>));

  Future<void> review(String orderId, int rating, String body) =>
      _guard(() async {
        await auth.authorizedJson('POST', 'leisure/orders/$orderId/review',
            body: {'rating': rating, 'body': body}, expected: {201});
      });

  Future<void> complain(String orderId, String body) => _guard(() async {
        await auth.authorizedJson('POST', 'leisure/complaints',
            body: {'orderId': orderId, 'body': body}, expected: {201});
      });

  Future<Set<String>> favorites() => _guard(() async =>
      ((await auth.authorizedJson('GET', 'leisure/favorites')) as List<dynamic>)
          .whereType<String>()
          .toSet());

  Future<void> setFavorite(String eventId, bool on) => _guard(() async {
        await auth.authorizedJson(
            on ? 'PUT' : 'DELETE', 'leisure/favorites/$eventId',
            expected: {204});
      });

  Future<List<EventCard>> favoriteCards(Set<String> ids) async {
    // The server lists favourite ids; cards come from the details so nothing is cached on the phone.
    final out = <EventCard>[];
    for (final id in ids) {
      try {
        final d = await event(id);
        out.add(EventCard(
          id: d.id,
          title: d.title,
          venueName: d.venue.name,
          district: d.venue.district,
          address: d.venue.address,
          categoryCode: d.category.code,
          bookingType: d.bookingType,
          photoUrl: d.photos.isEmpty ? null : d.photos.first,
          minPriceMinor: d.fromPriceMinor,
          minAge: d.minAge,
          familyFriendly: d.familyFriendly,
          rating: d.rating,
          reviewCount: d.reviewCount,
          nextSessionAt: DateTime.now(),
          nextSessionId: '',
          nextSessionFree: 0,
          distanceKm: null,
        ));
      } on LeisureException {
        // an event that is no longer public simply drops out of the list
      }
    }
    return out;
  }
}
