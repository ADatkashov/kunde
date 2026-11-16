import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Isolated Partner session storage; never shares the Consumer token key.
class PartnerSession {
  PartnerSession({
    required this.apiBase,
    http.Client? client,
    FlutterSecureStorage? storage,
  })  : _client = client ?? http.Client(),
        _storage = storage ?? const FlutterSecureStorage();

  final Uri apiBase;
  final http.Client _client;
  final FlutterSecureStorage _storage;
  static const _key = 'kunde.partner.session.v1';

  void _validateBase() {
    if (apiBase.scheme != 'https' ||
        apiBase.userInfo.isNotEmpty ||
        apiBase.hasQuery ||
        apiBase.hasFragment ||
        !apiBase.path.endsWith('/')) {
      throw const PartnerAuthException('INVALID_API_BASE');
    }
  }

  Future<Map<String, dynamic>> _post(
      String path, Map<String, dynamic> payload) async {
    _validateBase();
    final response = await _client
        .post(apiBase.resolve(path),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PartnerAuthException('HTTP_${response.statusCode}');
    }
    if (response.body.isEmpty) return {};
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const PartnerAuthException('INVALID_RESPONSE');
    }
    return decoded;
  }

  Future<void> requestOtp(String phone) async {
    await _post('auth/otp/request', {'phone': phone});
  }

  Future<void> verifyOtp(String phone, String code) async {
    final data = await _post('auth/otp/verify', {
      'phone': phone,
      'code': code,
    });
    final access = data['accessToken'];
    final refresh = data['refreshToken'];
    final expiresIn = data['expiresIn'];
    if (access is! String || access.isEmpty ||
        refresh is! String || refresh.isEmpty ||
        expiresIn is! num || expiresIn <= 0) {
      throw const PartnerAuthException('INVALID_RESPONSE');
    }
    await _storage.write(
      key: _key,
      value: jsonEncode({
        'base': apiBase.toString(),
        'refresh': refresh,
      }),
    );
    _access = access;
    _expires = DateTime.now().add(Duration(seconds: expiresIn.toInt()));
  }

  String? _access;
  DateTime? _expires;

  Future<String?> accessToken() async {
    if (_access != null &&
        _expires != null &&
        _expires!.isAfter(DateTime.now().add(const Duration(seconds: 30)))) {
      return _access;
    }
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    final saved = jsonDecode(raw);
    if (saved is! Map<String, dynamic> ||
        saved['base'] != apiBase.toString() ||
        saved['refresh'] is! String) {
      await clear();
      return null;
    }
    try {
      final refreshed = await _post('auth/token/refresh', {
        'refreshToken': saved['refresh'],
      });
      final access = refreshed['accessToken'];
      final refresh = refreshed['refreshToken'];
      final expiresIn = refreshed['expiresIn'];
      if (access is! String || access.isEmpty ||
          refresh is! String || refresh.isEmpty ||
          expiresIn is! num || expiresIn <= 0) {
        throw const PartnerAuthException('INVALID_RESPONSE');
      }
      await _storage.write(
          key: _key,
          value: jsonEncode({'base': apiBase.toString(), 'refresh': refresh}));
      _access = access;
      _expires = DateTime.now().add(Duration(seconds: expiresIn.toInt()));
      return access;
    } catch (_) {
      await clear();
      rethrow;
    }
  }

  Future<void> clear() async {
    _access = null;
    _expires = null;
    await _storage.delete(key: _key);
  }

  Future<void> logout() async {
    final raw = await _storage.read(key: _key);
    try {
      if (raw != null) {
        final saved = jsonDecode(raw);
        if (saved is Map<String, dynamic> &&
            saved['base'] == apiBase.toString() &&
            saved['refresh'] is String) {
          await _post('auth/logout', {'refreshToken': saved['refresh']});
        }
      }
    } finally {
      await clear();
    }
  }

  void dispose() => _client.close();
}

class PartnerAuthException implements Exception {
  const PartnerAuthException(this.code);
  final String code;
  @override
  String toString() => 'PartnerAuthException($code)';
}
