import 'dart:convert';
import 'package:http/http.dart' as http;

/// Typed, authenticated transport for existing KUNDE Partner Operations API.
///
/// Authentication and partner membership must be established by a separate
/// login/session flow. Never put a fixed token in the application bundle.
class PartnerApi {
  PartnerApi({
    required this.baseUri,
    required this.accessToken,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client();

  final Uri baseUri;
  final Future<String?> Function() accessToken;
  final http.Client _client;
  final Duration timeout;

  Uri _url(String path) {
    final prefix = baseUri.path.endsWith('/')
        ? baseUri.path
        : '${baseUri.path}/';
    final relative = Uri.parse(path.replaceFirst(RegExp(r'^/'), ''));
    return baseUri.replace(path: '$prefix${relative.path}', query: relative.hasQuery ? relative.query : null);
  }

  Future<Map<String, dynamic>> get(String path) => _request('GET', path);

  /// The partner membership endpoint returns a top-level JSON array.
  Future<List<Map<String, dynamic>>> myPartners() async {
    final token = await accessToken();
    if (token == null || token.isEmpty) {
      throw const PartnerApiException(401, 'AUTH_REQUIRED');
    }
    final response = await _client.get(
      _url('partner/partners'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        'Cache-Control': 'no-store',
      },
    ).timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PartnerApiException(response.statusCode, 'PARTNER_DISCOVERY_FAILED');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List || decoded.any((item) => item is! Map<String, dynamic>)) {
      throw const FormatException('Expected partner membership list');
    }
    return decoded.cast<Map<String, dynamic>>();
  }
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) =>
      _request('POST', path, body: body);
  Future<Map<String, dynamic>> patch(String path, Map<String, dynamic> body) =>
      _request('PATCH', path, body: body);

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final token = await accessToken();
    if (token == null || token.isEmpty) {
      throw const PartnerApiException(401, 'AUTH_REQUIRED');
    }
    final request = http.Request(method, _url(path))
      ..headers.addAll({
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        'Cache-Control': 'no-store',
        if (body != null) 'Content-Type': 'application/json',
      });
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(
      await _client.send(request).timeout(timeout),
    ).timeout(timeout);
    final decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PartnerApiException(response.statusCode, decoded.toString());
    }
    if (decoded is Map<String, dynamic>) return decoded;
    // Partner collection endpoints return top-level JSON arrays.
    // Normalize for existing list widgets without changing write responses.
    if (method == 'GET' && decoded is List &&
        decoded.every((item) => item is Map<String, dynamic>)) {
      return {'items': decoded.cast<Map<String, dynamic>>()};
    }
    throw const FormatException('Unexpected Partner API response structure');
  }

  void close() => _client.close();
}

class PartnerApiException implements Exception {
  const PartnerApiException(this.statusCode, this.message);
  final int statusCode;
  final String message;
  @override
  String toString() => 'PartnerApiException($statusCode, $message)';
}
