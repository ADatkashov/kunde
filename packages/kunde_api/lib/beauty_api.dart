import 'dart:convert';

import 'package:kunde_api/booking_api.dart';
import 'package:kunde_models/beauty_models.dart';

/// Beauty & Care discovery client. Shares transport, authorization and error mapping with [BookingApi];
/// bookings themselves still go through [BookingApi.book].
class BeautyApi {
  BeautyApi(this._booking);

  final BookingApi _booking;

  Future<dynamic> _json(String path, [Map<String, String>? query]) async =>
      jsonDecode(utf8.decode(
          (await _booking.publicResponse('beauty/$path', query)).bodyBytes));

  Future<List<BeautyCategory>> categories({bool? featured}) async =>
      ((await _json('categories', {
        if (featured != null) 'featured': '$featured',
        'limit': '50',
      })) as List<dynamic>)
          .map((e) => BeautyCategory.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);

  Future<BeautyPromotions> promotions() async => BeautyPromotions.fromJson(
      (await _json('promotions')) as Map<String, dynamic>);

  /// One page of salons; [total] is the server's `X-Total-Count` for the whole filtered list.
  Future<({List<BeautySalon> salons, int total})> salons(
    BeautySalonQuery query, {
    double? lat,
    double? lng,
    int limit = 20,
    int offset = 0,
  }) =>
      _booking.guarded(() async {
        final response = await _booking.publicResponse('beauty/salons', {
          'filter': query.filter.code,
          if (query.category != null) 'category': query.category!,
          if (query.text.trim().isNotEmpty) 'q': query.text.trim(),
          if (query.minPriceMinor != null)
            'minPriceMinor': '${query.minPriceMinor}',
          if (query.maxPriceMinor != null)
            'maxPriceMinor': '${query.maxPriceMinor}',
          if (query.maxDistanceMeters != null && lat != null && lng != null)
            'maxDistanceMeters': '${query.maxDistanceMeters}',
          if (query.verifiedOnly) 'verifiedOnly': 'true',
          if (lat != null && lng != null) ...{'lat': '$lat', 'lng': '$lng'},
          'limit': '$limit',
          'offset': '$offset',
        });
        final items =
            jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
        final salons = [
          for (final item in items)
            BeautySalon.fromJson(item as Map<String, dynamic>)
        ];
        return (
          salons: salons,
          total: int.tryParse(response.headers['x-total-count'] ?? '') ??
              offset + salons.length,
        );
      });

  Future<BeautySalonDetail> salon(String id) async =>
      BeautySalonDetail.fromJson(
          (await _json('salons/$id')) as Map<String, dynamic>);

  Future<BeautyServiceDetail> service(String id) async =>
      BeautyServiceDetail.fromJson(
          (await _json('services/$id')) as Map<String, dynamic>);

  /// Ids of the signed-in customer's favorite salons.
  Future<Set<String>> favorites() => _booking.guarded(() async =>
      ((await _booking.auth.authorizedJson('GET', 'beauty/favorites'))
              as List<dynamic>)
          .cast<String>()
          .toSet());

  Future<void> setFavorite(String salonId, bool saved) =>
      _booking.guarded(() async {
        await _booking.auth.authorizedJson(
          saved ? 'PUT' : 'DELETE',
          'beauty/favorites/$salonId',
          expected: const {204},
        );
      });
}
