import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:kunde_session/kunde_session.dart';

import '../data/errors.dart';

export '../data/errors.dart' show PartnerAuthException, SessionExpiredException;
export 'package:kunde_session/kunde_session.dart'
    show SecureKeyValue, FlutterSecureKeyValue;

/// The Partner adapter of the shared token-session core (ADR-024): its own storage key and format
/// (`base`, `refresh`, `partnerId`), its own OTP and refresh endpoints and its own error types.
///
/// The refresh token (and the chosen partner) live in platform secure storage under a Partner-only key, never the
/// Consumer one. The short-lived access token is kept in memory only. Refresh is single flight (in the core), so
/// concurrent requests never spend a rotating refresh token twice.
class PartnerSession {
  PartnerSession({
    required this.apiBase,
    http.Client? client,
    SecureKeyValue? storage,
    this.timeout = const Duration(seconds: 20),
  })  : _client = client ?? http.Client(),
        _storage = storage ?? const FlutterSecureKeyValue() {
    _core = TokenSession(
      persistence: _PartnerPersistence(_storage, apiBase.toString()),
      refresher: _PartnerRefresher(this),
      carryExtrasAcrossSignIn: true,
    );
  }

  final Uri apiBase;
  final http.Client _client;
  final SecureKeyValue _storage;
  final Duration timeout;
  static const _key = 'kunde.partner.session.v1';
  late final TokenSession _core;

  /// Called once when the server rejects the stored refresh token.
  void Function()? get onExpired => _core.onExpired;
  set onExpired(void Function()? callback) => _core.onExpired = callback;

  // The isolated Android CI fixture uses an ADB reverse tunnel to loopback.
  bool get _localFixture =>
      kDebugMode &&
      const bool.fromEnvironment('PARTNER_LOCAL_FIXTURE') &&
      apiBase.scheme == 'http' &&
      apiBase.host == 'localhost' &&
      apiBase.port == 8081;

  bool get baseIsValid =>
      (apiBase.scheme == 'https' || _localFixture) &&
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
      if (_rejects(e)) {
        throw const PartnerAuthException(PartnerAuthException.wrongCode);
      }
      rethrow;
    }
    await _core.signIn(_issue(data));
  }

  static bool _rejects(PartnerAuthException e) =>
      e.code == 'HTTP_400' || e.code == 'HTTP_401' || e.code == 'HTTP_403';

  /// Validates a token response (access, rotating refresh, lifetime).
  static IssuedTokens _issue(Map<String, dynamic> data) {
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
    return IssuedTokens(
        access: access,
        refresh: refresh,
        expires: DateTime.now().add(Duration(seconds: expiresIn.toInt())));
  }

  /// Whether a refresh token for this API base is stored (no network).
  Future<bool> hasStoredSession() async => await _core.peek() != null;

  Future<String?> storedPartnerId() async =>
      (await _core.peek())?.extras['partnerId'];

  Future<void> rememberPartner(String? partnerId) =>
      _core.updateExtras({'partnerId': partnerId});

  /// A valid access token, refreshing if needed. Returns null when there is no
  /// stored session. Throws [SessionExpiredException] when the server rejects
  /// the refresh token (the session is cleared) and [PartnerAuthException]
  /// (network/timeout) on a transient failure (the session is kept).
  Future<String?> accessToken({bool force = false}) async {
    try {
      return await _core.accessToken(force: force);
    } on SessionMissing {
      return null;
    } on SessionRejected {
      throw const SessionExpiredException();
    } on SessionUnavailable catch (e) {
      final cause = e.cause;
      throw cause is PartnerAuthException
          ? cause
          : const PartnerAuthException(PartnerAuthException.network);
    }
  }

  Future<void> clear() => _core.discard();

  Future<void> logout() async {
    await _core.signOut(
        revoke: (stored) =>
            _post('auth/logout', {'refreshToken': stored.refresh}));
  }

  void dispose() {
    _core.dispose();
    _client.close();
  }
}

class _PartnerRefresher implements TokenRefresher {
  _PartnerRefresher(this._session);
  final PartnerSession _session;

  @override
  Future<IssuedTokens> refresh(String refreshToken) async {
    try {
      return PartnerSession._issue(await _session
          ._post('auth/token/refresh', {'refreshToken': refreshToken}));
    } on PartnerAuthException catch (e) {
      if (PartnerSession._rejects(e)) throw SessionRejected(e);
      throw SessionUnavailable(e);
    }
  }
}

/// Stored format of installed Partner apps: `{base, refresh, partnerId?}`. State for another API base or
/// unreadable state is discarded silently (no expiry), as before.
class _PartnerPersistence implements SessionPersistence {
  _PartnerPersistence(this._storage, this._base);
  final SecureKeyValue _storage;
  final String _base;

  @override
  Future<StoredSession?> load() async {
    final raw = await _storage.read(PartnerSession._key);
    if (raw == null) return null;
    try {
      final saved = jsonDecode(raw);
      if (saved is Map<String, dynamic> &&
          saved['base'] == _base &&
          saved['refresh'] is String &&
          (saved['refresh'] as String).isNotEmpty) {
        final partnerId = saved['partnerId'];
        return StoredSession(saved['refresh'] as String,
            {if (partnerId is String) 'partnerId': partnerId});
      }
    } on FormatException {
      // fall through: unreadable state is discarded
    }
    await _storage.delete(PartnerSession._key);
    return null;
  }

  @override
  Future<void> save(StoredSession session) => _storage.write(
      PartnerSession._key,
      jsonEncode({
        'base': _base,
        'refresh': session.refresh,
        if (session.extras['partnerId'] != null)
          'partnerId': session.extras['partnerId'],
      }));

  @override
  Future<void> clear() => _storage.delete(PartnerSession._key);
}
