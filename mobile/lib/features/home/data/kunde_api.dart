import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'catalog_category.dart';
import 'catalog_offering.dart';
import 'platform_snapshot.dart';

class KundeApiException implements Exception {
  const KundeApiException(this.kind);

  final KundeApiFailure kind;
}

enum KundeApiFailure { unavailable, unexpectedResponse }

class KundeApi {
  KundeApi({
    required Uri baseUri,
    http.Client? client,
    this.timeout = const Duration(seconds: 4),
  })  : _baseUri = baseUri.toString().endsWith('/')
            ? baseUri
            : baseUri.replace(path: '${baseUri.path}/'),
        _client = client ?? http.Client();

  final Uri _baseUri;
  final http.Client _client;
  final Duration timeout;

  Future<PlatformSnapshot> loadPlatformSnapshot() async {
    try {
      final response =
          await _client.get(_baseUri.resolve('capabilities')).timeout(timeout);
      if (response.statusCode != 200) {
        throw const KundeApiException(KundeApiFailure.unavailable);
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const KundeApiException(KundeApiFailure.unexpectedResponse);
      }
      return PlatformSnapshot.fromJson(decoded);
    } on TimeoutException {
      throw const KundeApiException(KundeApiFailure.unavailable);
    } on FormatException {
      throw const KundeApiException(KundeApiFailure.unexpectedResponse);
    } on KundeApiException {
      rethrow;
    } catch (_) {
      throw const KundeApiException(KundeApiFailure.unavailable);
    }
  }

  Future<List<CatalogCategory>> searchCategories(String query) =>
      _searchList('search', query, CatalogCategory.fromJson);

  Future<List<CatalogOffering>> searchOfferings(String query) =>
      _searchList('search/offerings', query, CatalogOffering.fromJson);

  Future<List<T>> _searchList<T>(
      String path, String query, T Function(Map<String, dynamic>) parse) async {
    try {
      final uri = _baseUri.resolve(path).replace(queryParameters: {'q': query});
      final response = await _client.get(uri).timeout(timeout);
      if (response.statusCode != 200) {
        throw const KundeApiException(KundeApiFailure.unavailable);
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        throw const KundeApiException(KundeApiFailure.unexpectedResponse);
      }
      return decoded.map((item) {
        if (item is! Map<String, dynamic>) {
          throw const FormatException('Invalid catalog response');
        }
        return parse(item);
      }).toList(growable: false);
    } on TimeoutException {
      throw const KundeApiException(KundeApiFailure.unavailable);
    } on FormatException {
      throw const KundeApiException(KundeApiFailure.unexpectedResponse);
    } on KundeApiException {
      rethrow;
    } catch (_) {
      throw const KundeApiException(KundeApiFailure.unavailable);
    }
  }

  void close() => _client.close();
}
