import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class SessionExpired implements Exception {}

class IdentityUnavailable implements Exception {}

class AuthTokens {
  const AuthTokens(this.access, this.refresh, this.id, this.expires);
  final String access;
  final String refresh;
  final String? id;
  final DateTime expires;
}

abstract interface class TokenVault {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

class SecureTokenVault implements TokenVault {
  static const _storage = FlutterSecureStorage(
      iOptions: IOSOptions(
          accessibility: KeychainAccessibility.unlocked_this_device));
  static const _key = 'kunde.consumer.session.v1';
  @override
  Future<String?> read() => _storage.read(key: _key);
  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);
  @override
  Future<void> clear() => _storage.delete(key: _key);
}

abstract interface class OAuthGateway {
  Future<AuthTokens> login({bool register = false});
  Future<AuthTokens> refresh(String refreshToken);
  Future<void> logout(String? idToken);
}

class AppAuthGateway implements OAuthGateway {
  AppAuthGateway({
    required String issuer,
    required this.clientId,
    this.redirect = 'com.kunde.mobile:/oauth2redirect',
  }) : issuer = issuer.endsWith('/')
            ? issuer.substring(0, issuer.length - 1)
            : issuer;
  final String issuer;
  final String clientId;
  final String redirect;
  static const _auth = FlutterAppAuth();
  static const _scopes = ['openid', 'profile', 'kunde.consumer'];

  bool get _allowHttp {
    final uri = Uri.parse(issuer);
    return kDebugMode &&
        uri.scheme == 'http' &&
        ['localhost', '127.0.0.1', '::1'].contains(uri.host);
  }

  void _validate() {
    final uri = Uri.parse(issuer);
    if (clientId.isEmpty ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.hasQuery ||
        (uri.scheme != 'https' && !_allowHttp)) {
      throw IdentityUnavailable();
    }
  }

  AuthTokens _tokens(TokenResponse response) {
    final access = response.accessToken;
    final refresh = response.refreshToken;
    final expires = response.accessTokenExpirationDateTime;
    if (access == null ||
        access.isEmpty ||
        refresh == null ||
        refresh.isEmpty ||
        expires == null ||
        !expires.isAfter(DateTime.now())) {
      throw SessionExpired();
    }
    return AuthTokens(access, refresh, response.idToken, expires);
  }

  @override
  Future<AuthTokens> login({bool register = false}) async {
    _validate();
    return _tokens(
      await _auth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          clientId,
          redirect,
          issuer: register ? null : issuer,
          serviceConfiguration: register
              ? AuthorizationServiceConfiguration(
                  authorizationEndpoint:
                      '$issuer/protocol/openid-connect/registrations',
                  tokenEndpoint: '$issuer/protocol/openid-connect/token',
                  endSessionEndpoint: '$issuer/protocol/openid-connect/logout',
                )
              : null,
          scopes: _scopes,
          allowInsecureConnections: _allowHttp,
        ),
      ),
    );
  }

  @override
  Future<AuthTokens> refresh(String refreshToken) async {
    _validate();
    try {
      return _tokens(
        await _auth.token(
          TokenRequest(
            clientId,
            redirect,
            issuer: issuer,
            refreshToken: refreshToken,
            scopes: _scopes,
            allowInsecureConnections: _allowHttp,
          ),
        ),
      );
    } on FlutterAppAuthPlatformException catch (error) {
      final code = error.platformErrorDetails.error;
      if (code == 'invalid_grant' || code == 'invalid_token') {
        throw SessionExpired();
      }
      if (code == null ||
          code == 'server_error' ||
          code == 'temporarily_unavailable' ||
          code == 'network_error') {
        throw IdentityUnavailable();
      }
      throw SessionExpired();
    } on PlatformException {
      // Native transport errors without OAuth details do not confirm revocation.
      throw IdentityUnavailable();
    }
  }

  @override
  Future<void> logout(String? idToken) async {
    _validate();
    if (idToken == null) throw IdentityUnavailable();
    await _auth.endSession(
      EndSessionRequest(
        issuer: issuer,
        idTokenHint: idToken,
        postLogoutRedirectUrl: redirect,
        allowInsecureConnections: _allowHttp,
      ),
    );
  }
}

class AuthRepository extends ChangeNotifier {
  AuthRepository({
    required this.gateway,
    required this.vault,
    required this.apiBase,
    http.Client? client,
  }) : _client = client ?? http.Client() {
    final local = kDebugMode &&
        apiBase.scheme == 'http' &&
        ['localhost', '127.0.0.1', '10.0.2.2', '::1'].contains(apiBase.host);
    if ((apiBase.scheme != 'https' && !local) ||
        apiBase.userInfo.isNotEmpty ||
        apiBase.hasFragment ||
        apiBase.hasQuery ||
        !apiBase.path.endsWith('/')) {
      throw IdentityUnavailable();
    }
  }
  final OAuthGateway gateway;
  final TokenVault vault;
  final Uri apiBase;
  final http.Client _client;
  Future<void> _tail = Future.value();
  AuthTokens? _tokens;
  bool expired = false;
  bool get authenticated => _tokens != null;
  String get _context => gateway is AppAuthGateway
      ? '${(gateway as AppAuthGateway).issuer}|${(gateway as AppAuthGateway).clientId}|$apiBase'
      : apiBase.toString();

  Future<T> _exclusive<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> _replace(AuthTokens tokens) async {
    await vault.write(
      jsonEncode({
        'issuerVersion': 2,
        'context': _context,
        'refresh': tokens.refresh,
        'id': tokens.id,
      }),
    );
    _tokens = tokens;
    expired = false;
    notifyListeners();
  }

  Future<void> _invalidate({bool sessionExpired = true}) async {
    _tokens = null;
    expired = sessionExpired;
    notifyListeners();
    await vault.clear();
  }

  Future<void> restore() => _exclusive(() async {
        try {
          final saved = await vault.read();
          if (saved == null) return;
          final value = jsonDecode(saved) as Map<String, dynamic>;
          if (value['issuerVersion'] != 2 || value['context'] != _context) {
            throw SessionExpired();
          }
          final refresh = value['refresh'] as String;
          if (refresh.isEmpty) throw SessionExpired();
          final refreshed = await gateway.refresh(refresh);
          await _replace(AuthTokens(refreshed.access, refreshed.refresh,
              refreshed.id ?? value['id'] as String?, refreshed.expires));
        } on IdentityUnavailable {
          rethrow;
        } catch (_) {
          await _invalidate();
        }
      });

  Future<void> login({bool register = false}) => _exclusive(() async {
        try {
          final tokens = await gateway.login(register: register);
          await _replace(tokens);
        } catch (_) {
          await _invalidate(sessionExpired: false);
          rethrow;
        }
      });

  Future<String> accessToken() => _exclusive(() async {
        final current = _tokens;
        if (current == null) throw SessionExpired();
        if (current.expires.isAfter(
          DateTime.now().add(const Duration(seconds: 30)),
        )) {
          return current.access;
        }
        try {
          final refreshed = await gateway.refresh(current.refresh);
          await _replace(AuthTokens(refreshed.access, refreshed.refresh,
              refreshed.id ?? current.id, refreshed.expires));
          return _tokens!.access;
        } on IdentityUnavailable {
          rethrow;
        } catch (_) {
          await _invalidate();
          throw SessionExpired();
        }
      });

  Future<Map<String, dynamic>> profile() => _request('GET');
  Future<Map<String, dynamic>> updateProfile(
    String name,
    String language,
    int version,
  ) =>
      _request('PATCH', {
        'displayName': name,
        'preferredLanguage': language,
        'version': version,
      });

  Future<List<Map<String, dynamic>>> addresses() async {
    final result = await _requestJson('GET', 'me/addresses');
    return (result as List<dynamic>)
        .map((entry) => entry as Map<String, dynamic>)
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> createAddress({
    required String label,
    required String formattedAddress,
    required double latitude,
    required double longitude,
  }) async {
    if (label.trim().isEmpty ||
        label.length > 80 ||
        formattedAddress.trim().isEmpty ||
        formattedAddress.length > 500 ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      throw ArgumentError('Invalid address');
    }
    return (await _requestJson('POST', 'me/addresses', {
      'label': label.trim(),
      'formattedAddress': formattedAddress.trim(),
      'latitude': latitude,
      'longitude': longitude,
    }, {
      201
    })) as Map<String, dynamic>;
  }

  Future<void> deleteAddress(String id, int version) async {
    final pieces = id.split('-');
    if (pieces.map((s) => s.length).join(',') != '8,4,4,4,12' ||
        !RegExp(r'^[0-9a-fA-F]+').hasMatch(id.replaceAll('-', '')) ||
        id.replaceAll('-', '').length != 32 ||
        version < 0) {
      throw ArgumentError('Invalid address identity or version');
    }
    await _requestJson(
        'DELETE', 'me/addresses/$id?version=$version', null, {204});
  }

  Future<List<Map<String, dynamic>>> consents() async {
    final result = await _requestJson('GET', 'me/consents');
    return (result as List<dynamic>)
        .map((entry) => entry as Map<String, dynamic>)
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> setConsent(String policyId, bool granted) async {
    final segments = policyId.split('-');
    if (segments.length != 5 ||
        segments.map((s) => s.length).join(',') != '8,4,4,4,12' ||
        !RegExp(r'^[0-9a-fA-F]+').hasMatch(policyId.replaceAll('-', '')) ||
        policyId.replaceAll('-', '').length != 32) {
      throw ArgumentError.value(policyId, 'policyId', 'Invalid policy ID');
    }
    return (await _requestJson(
            granted ? 'PUT' : 'DELETE', 'me/consents/$policyId'))
        as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _request(
    String method, [
    Map<String, dynamic>? body,
  ]) async =>
      (await _requestJson(method, 'me', body)) as Map<String, dynamic>;

  Future<dynamic> _requestJson(
    String method,
    String path, [
    Map<String, dynamic>? body,
    Set<int> expected = const {200},
  ]) async {
    final access = await accessToken();
    final request = http.Request(method, apiBase.resolve(path));
    request.headers.addAll({
      'Authorization': 'Bearer $access',
      'Accept': 'application/json',
    });
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final http.Response response;
    try {
      response = await (() async =>
              http.Response.fromStream(await _client.send(request)))()
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw IdentityUnavailable();
    } on http.ClientException {
      throw IdentityUnavailable();
    }
    if (response.statusCode == 401) {
      await _exclusive(() async {
        if (_tokens?.access == access) await _invalidate();
      });
      throw SessionExpired();
    }
    if (!expected.contains(response.statusCode)) {
      throw IdentityApiError(response.statusCode);
    }
    if (response.statusCode == 204) return null;
    return jsonDecode(response.body);
  }

  Future<bool> logout() => _exclusive(() async {
        final id = _tokens?.id;
        _tokens = null;
        expired = false;
        notifyListeners();
        await vault.clear();
        try {
          await gateway.logout(id);
          return true;
        } catch (_) {
          return false;
        }
      });

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }
}

class IdentityApiError implements Exception {
  IdentityApiError(this.status);
  final int status;
}
