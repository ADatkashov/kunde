import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

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

  Future<Map<String, dynamic>> loadEducationCourses({
    required String query,
    required String format,
    required int offset,
  }) =>
      _educationJson('education/courses', {
        'q': query,
        if (format.isNotEmpty) 'format': format,
        'offset': offset.toString(),
      });

  Future<Map<String, dynamic>> loadEducationCourse(String id) =>
      _educationJson('education/courses/${Uri.encodeComponent(id)}');

  Future<Map<String, dynamic>> _educationJson(
    String path, [
    Map<String, String>? params,
  ]) async {
    final response = await _client
        .get(_baseUri.resolve(path).replace(queryParameters: params))
        .timeout(timeout);
    if (response.statusCode != 200) {
      throw const KundeApiException(KundeApiFailure.unavailable);
    }
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  Future<List<dynamic>> educationCohorts(String course) async =>
      await educationRequest('courses/$course/cohorts') as List<dynamic>;

  Future<dynamic> educationRequest(
    String path, {
    String? token,
    String method = 'GET',
    Map<String, dynamic>? body,
    String? key,
  }) async {
    final request = http.Request(method, _baseUri.resolve('education/$path'));
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (key != null) request.headers['Idempotency-Key'] = key;
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final response = await _client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const KundeApiException(KundeApiFailure.unavailable);
    }
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  Future<Uint8List> educationCertificatePdf(
      String enrollmentId, String token) async {
    final response = await _client.get(
      _baseUri.resolve(
          'education/enrollments/${Uri.encodeComponent(enrollmentId)}/certificate.pdf'),
      headers: {'Authorization': 'Bearer $token', 'Accept': 'application/pdf'},
    ).timeout(timeout);
    if (response.statusCode != 200 ||
        response.bodyBytes.isEmpty ||
        response.headers['content-type']?.startsWith('application/pdf') !=
            true) {
      throw const KundeApiException(KundeApiFailure.unavailable);
    }
    return response.bodyBytes;
  }

  void close() => _client.close();
}
