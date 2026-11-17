import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../data/errors.dart';

export '../data/errors.dart' show PartnerAuthException, SessionExpiredException;

/// Minimal key/value contract so the token store can be faked in tests.
abstract interface class SecureKeyValue {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterSecureKeyValue implements SecureKeyValue {
  const FlutterSecureKeyValue([this._s = const FlutterSecureStorage()]);
  final FlutterSecureStorage _s;
  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _s.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _s.delete(key: key);
}

/// Isolated Partner session storage; never shares the Consumer token key.
///
/// The refresh token (and the chosen partner) live in platform secure storage.
/// The short-lived access token is kept in memory only. Refresh is single
/// flight so concurrent requests never spend a rotating refresh token twice.
class PartnerSession {
  PartnerSession({
    required this.apiBase,
    http.Client? client,
    SecureKeyValue? storage,
    this.timeout = const Duration(seconds: 20),
  })  : _client = client ?? http.Client(),
        _storage = storage ?? const FlutterSecureKeyValue();

  final Uri apiBase;
  final http.Client _client;
  final SecureKeyValue _storage;
  final Duration timeout;
  static const _key = 'kunde.partner.session.v1';

  /// Called once when the server rejects the stored refresh token.
  void Function()? onExpired;

  String? _access;
  DateTime? _expires;
  Future<String?>? _refreshing;

  bool get baseIsValid =>
      apiBase.scheme == 'https' &&
      apiBase.host.isNotEmpty &&
      apiBase.userInfo.isEmpty &&
      !apiBase.hasQuery &&
      !apiBase.hasFragment &&
      apiBase.path.endsWith('/');

  Future<Map<String, dynamic>> _post(
      String path, Map<String, dynamic> payload) async {
    if (!baseIsValid) {
      throw const PartnerAuthException(PartnerAuthException.invalidApiBase);
    }
    final http.Response response;
    try {
      response = await _client
          .post(apiBase.resolve(path),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(payload))
          .timeout(timeout);
    } on TimeoutException {
      throw const PartnerAuthException(PartnerAuthException.timeout);
    } on SocketException {
      throw const PartnerAuthException(PartnerAuthException.network);
    } on http.ClientException {
      throw const PartnerAuthException(PartnerAuthException.network);
    }
    final status = response.statusCode;
    if (status == 429) {
      throw const PartnerAuthException(PartnerAuthException.rateLimited);
    }
    if (status < 200 || status >= 300) {
      throw PartnerAuthException('HTTP_$status');
    }
    if (response.bodyBytes.isEmpty) return {};
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const PartnerAuthException(PartnerAuthException.invalidResponse);
    }
    if (decoded is! Map<String, dynamic>) {
      throw const PartnerAuthException(PartnerAuthException.invalidResponse);
    }
    return decoded;
  }

  Future<void> requestOtp(String phone) async {
    await _post('auth/otp/request', {'phone': phone});
  }

  Future<void> verifyOtp(String phone, String code) async {
    final Map<String, dynamic> data;
    try {
      data = await _post('auth/otp/verify', {'phone': phone, 'code': code});
    } on PartnerAuthException catch (e) {
      if (e.code == 'HTTP_400' ||
          e.code == 'HTTP_401' ||
          e.code == 'HTTP_403') {
        throw const PartnerAuthException(PartnerAuthException.wrongCode);
      }
      rethrow;
    }
    await _accept(data);
    await _writeStored(refresh: data['refreshToken'] as String);
  }

  /// Validates a token response and keeps the access token in memory.
  Future<String> _accept(Map<String, dynamic> data) async {
    final access = data['accessToken'];
    final refresh = data['refreshToken'];
    final expiresIn = data['expiresIn'];
    if (access is! String ||
        access.isEmpty ||
        refresh is! String ||
        refresh.isEmpty ||
        expiresIn is! num ||
        expiresIn <= 0) {
      throw const PartnerAuthException(PartnerAuthException.invalidResponse);
    }
    _access = access;
    _expires = DateTime.now().add(Duration(seconds: expiresIn.toInt()));
    return access;
  }

  Future<Map<String, dynamic>?> _readStored() async {
    final raw = await _storage.read(_key);
    if (raw == null) return null;
    try {
      final saved = jsonDecode(raw);
      if (saved is Map<String, dynamic> &&
          saved['base'] == apiBase.toString() &&
          saved['refresh'] is String &&
          (saved['refresh'] as String).isNotEmpty) {
        return saved;
      }
    } on FormatException {
      // fall through: unreadable state is discarded
    }
    await _storage.delete(_key);
    return null;
  }

  Future<void> _writeStored(
      {String? refresh, Object? partnerId = _keep}) async {
    final current = await _readStored();
    final Object? previous = current == null ? null : current['partnerId'];
    final Object? chosen = identical(partnerId, _keep) ? previous : partnerId;
    final next = <String, dynamic>{
      'base': apiBase.toString(),
      'refresh': refresh ?? current?['refresh'],
      if (chosen != null) 'partnerId': chosen,
    };
    await _storage.write(_key, jsonEncode(next));
  }

  static const Object _keep = Object();

  /// Whether a refresh token for this API base is stored (no network).
  Future<bool> hasStoredSession() async => await _readStored() != null;

  Future<String?> storedPartnerId() async =>
      (await _readStored())?['partnerId'] as String?;

  Future<void> rememberPartner(String? partnerId) async {
    if (await _readStored() == null) return;
    await _writeStored(partnerId: partnerId);
  }

  /// A valid access token, refreshing if needed. Returns null when there is no
  /// stored session. Throws [SessionExpiredException] when the server rejects
  /// the refresh token (the session is cleared) and [PartnerAuthException]
  /// (network/timeout) on a transient failure (the session is kept).
  Future<String?> accessToken({bool force = false}) {
    if (!force &&
        _access != null &&
        _expires != null &&
        _expires!.isAfter(DateTime.now().add(const Duration(seconds: 30)))) {
      return Future.value(_access);
    }
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<String?> _refresh() async {
    final saved = await _readStored();
    if (saved == null) return null;
    try {
      final refreshed =
          await _post('auth/token/refresh', {'refreshToken': saved['refresh']});
      final access = await _accept(refreshed);
      await _writeStored(refresh: refreshed['refreshToken'] as String);
      return access;
    } on PartnerAuthException catch (e) {
      final rejected =
          e.code == 'HTTP_400' || e.code == 'HTTP_401' || e.code == 'HTTP_403';
      if (rejected) {
        await clear();
        onExpired?.call();
        throw const SessionExpiredException();
      }
      rethrow;
    }
  }

  Future<void> clear() async {
    _access = null;
    _expires = null;
    await _storage.delete(_key);
  }

  Future<void> logout() async {
    final saved = await _readStored();
    try {
      if (saved != null) {
        await _post('auth/logout', {'refreshToken': saved['refresh']});
      }
    } on Object {
      // The local session is always cleared, even when the server is offline.
    } finally {
      await clear();
    }
  }

  void dispose() => _client.close();
}
