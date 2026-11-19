import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'errors.dart';

export 'errors.dart' show PartnerApiException, ApiErrorKind;

/// Typed, authenticated transport for the existing KUNDE Partner API.
///
/// * Never embeds a token: [accessToken] comes from the session.
/// * A 401 triggers exactly one token refresh and one replay of the request.
/// * Only idempotent GETs are retried on connectivity problems (not on timeouts); POST/PATCH/PUT
///   are sent once so a user action is never duplicated.
class PartnerApi {
  PartnerApi({
    required this.baseUri,
    required this.accessToken,
    this.forceRefresh,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
    this.getRetries = 2,
    this.retryDelay = const Duration(milliseconds: 600),
  }) : _client = client ?? http.Client();

  final Uri baseUri;
  final Future<String?> Function() accessToken;

  /// Obtains a fresh access token after a 401; null disables the replay.
  final Future<String?> Function()? forceRefresh;
  final http.Client _client;
  final Duration timeout;
  final int getRetries;
  final Duration retryDelay;

  Uri _url(String path) {
    final prefix =
        baseUri.path.endsWith('/') ? baseUri.path : '${baseUri.path}/';
    final relative = Uri.parse(path.replaceFirst(RegExp(r'^/'), ''));
    return baseUri.replace(
        path: '$prefix${relative.path}',
        query: relative.hasQuery ? relative.query : null);
  }

  Future<Object?> getJson(String path) => _send('GET', path);
  Future<Object?> postJson(String path, Map<String, dynamic> body) =>
      _send('POST', path, body: body);
  Future<Object?> patchJson(String path, Map<String, dynamic> body) =>
      _send('PATCH', path, body: body);
  Future<Object?> putJson(String path, Map<String, dynamic> body) =>
      _send('PUT', path, body: body);
  Future<Object?> deleteJson(String path) => _send('DELETE', path);

  /// GET that must return a top-level JSON array of objects.
  Future<List<Map<String, dynamic>>> getList(String path) async {
    final decoded = await getJson(path);
    if (decoded is List && decoded.every((e) => e is Map<String, dynamic>)) {
      return decoded.cast<Map<String, dynamic>>();
    }
    throw const FormatException('Expected a JSON array of objects');
  }

  Future<Map<String, dynamic>> getMap(String path) async =>
      _asMap(await getJson(path));
  Future<Map<String, dynamic>> postMap(String path, Map<String, dynamic> body,
          {String? idempotencyKey}) async =>
      _asMap(await _send('POST', path,
          body: body, idempotencyKey: idempotencyKey));
  Future<Map<String, dynamic>> putMap(
          String path, Map<String, dynamic> body) async =>
      _asMap(await putJson(path, body));
  Future<Map<String, dynamic>> patchMap(
          String path, Map<String, dynamic> body) async =>
      _asMap(await patchJson(path, body));

  static Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    throw const FormatException('Expected a JSON object');
  }

  Future<Object?> _send(String method, String path,
      {Map<String, dynamic>? body, String? idempotencyKey}) async {
    final maxAttempts = method == 'GET' ? 1 + getRetries : 1;
    PartnerApiException? last;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (attempt > 0) await Future<void>.delayed(retryDelay * attempt);
      try {
        return await _once(method, path,
            body: body, idempotencyKey: idempotencyKey);
      } on PartnerApiException catch (e) {
        last = e;
        // A timeout is not retried: the server is slow, not unreachable, and
        // a repeat would only add load. Cold-start answers (502/503/504) are.
        final transient = e.kind == ApiErrorKind.network ||
            e.statusCode == 502 ||
            e.statusCode == 503 ||
            e.statusCode == 504;
        if (!transient) rethrow;
      }
    }
    throw last!;
  }

  Future<Object?> _once(String method, String path,
      {Map<String, dynamic>? body,
      String? idempotencyKey,
      bool replayed = false}) async {
    final token = await accessToken();
    if (token == null || token.isEmpty) {
      throw const PartnerApiException(401, 'AUTH_REQUIRED');
    }
    final request = http.Request(method, _url(path))
      ..headers.addAll({
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        'Cache-Control': 'no-store',
        if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
        if (body != null) 'Content-Type': 'application/json; charset=utf-8',
      });
    if (body != null) request.body = jsonEncode(body);
    final http.Response response;
    try {
      final streamed = await _client.send(request).timeout(timeout);
      response = await http.Response.fromStream(streamed).timeout(timeout);
    } on TimeoutException {
      throw const PartnerApiException(0, 'TIMEOUT', kind: ApiErrorKind.timeout);
    } on SocketException {
      throw const PartnerApiException(0, 'NETWORK', kind: ApiErrorKind.network);
    } on http.ClientException {
      throw const PartnerApiException(0, 'NETWORK', kind: ApiErrorKind.network);
    }
    if (response.statusCode == 401 && !replayed && forceRefresh != null) {
      final fresh = await forceRefresh!();
      if (fresh != null && fresh.isNotEmpty) {
        return _once(method, path,
            body: body, idempotencyKey: idempotencyKey, replayed: true);
      }
    }
    Object? decoded;
    if (response.bodyBytes.isNotEmpty) {
      try {
        // Spring answers `application/json` without a charset; decode UTF-8
        // explicitly so Cyrillic/Kazakh names are never mangled.
        decoded = jsonDecode(utf8.decode(response.bodyBytes));
      } on FormatException {
        decoded = null;
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String? code;
      String message = 'HTTP_${response.statusCode}';
      if (decoded is Map<String, dynamic>) {
        final c = decoded['code'];
        if (c is String && c.isNotEmpty) code = c;
        final m = decoded['message'];
        if (m is String && m.isNotEmpty) message = m;
      }
      throw PartnerApiException(response.statusCode, message, code: code);
    }
    return decoded;
  }

  void close() => _client.close();
}
