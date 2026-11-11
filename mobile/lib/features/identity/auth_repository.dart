import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
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
  static const _storage = FlutterSecureStorage();
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
  AppAuthGateway(
      {required this.issuer,
      required this.clientId,
      this.redirect = 'com.kunde.mobile:/oauth2redirect'});
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
        (uri.scheme != 'https' && !_allowHttp)) {
      throw IdentityUnavailable();
    }
  }

  AuthTokens _tokens(TokenResponse response) {
    final access = response.accessToken;
    final refresh = response.refreshToken;
    final expires = response.accessTokenExpirationDateTime;
    if (access == null || refresh == null || expires == null) {
      throw SessionExpired();
    }
    return AuthTokens(access, refresh, response.idToken, expires);
  }

  @override
  Future<AuthTokens> login({bool register = false}) async {
    _validate();
    return _tokens(await _auth.authorizeAndExchangeCode(
      AuthorizationTokenRequest(clientId, redirect,
          issuer: issuer,
          scopes: _scopes,
          allowInsecureConnections: _allowHttp,
          additionalParameters: register ? {'kc_action': 'register'} : null),
    ));
  }

  @override
  Future<AuthTokens> refresh(String refreshToken) async {
    _validate();
    return _tokens(await _auth.token(TokenRequest(clientId, redirect,
        issuer: issuer,
        refreshToken: refreshToken,
        scopes: _scopes,
        allowInsecureConnections: _allowHttp)));
  }

  @override
  Future<void> logout(String? idToken) async {
    _validate();
    if (idToken == null) throw IdentityUnavailable();
    await _auth.endSession(EndSessionRequest(
        issuer: issuer,
        idTokenHint: idToken,
        postLogoutRedirectUrl: redirect,
        allowInsecureConnections: _allowHttp));
  }
}

class AuthRepository extends ChangeNotifier {
  AuthRepository(
      {required this.gateway,
      required this.vault,
      required this.apiBase,
      http.Client? client})
      : _client = client ?? http.Client() {
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

  Future<T> _exclusive<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> _replace(AuthTokens tokens) async {
    await vault.write(jsonEncode(
        {'issuerVersion': 1, 'refresh': tokens.refresh, 'id': tokens.id}));
    _tokens = tokens;
    expired = false;
    notifyListeners();
  }

  Future<void> _invalidate() async {
    _tokens = null;
    expired = true;
    notifyListeners();
    await vault.clear();
  }

  Future<void> restore() => _exclusive(() async {
        try {
          final saved = await vault.read();
          if (saved == null) return;
          final value = jsonDecode(saved) as Map<String, dynamic>;
          final refresh = value['refresh'] as String;
          await vault.clear();
          await _replace(await gateway.refresh(refresh));
        } catch (_) {
          await _invalidate();
        }
      });

  Future<void> login({bool register = false}) => _exclusive(() async {
        try {
          final tokens = await gateway.login(register: register);
          await _replace(tokens);
        } catch (_) {
          await _invalidate();
          rethrow;
        }
      });

  Future<String> accessToken() => _exclusive(() async {
        final current = _tokens;
        if (current == null) throw SessionExpired();
        if (current.expires
            .isAfter(DateTime.now().add(const Duration(seconds: 30)))) {
          return current.access;
        }
        try {
          await vault.clear();
          await _replace(await gateway.refresh(current.refresh));
          return _tokens!.access;
        } catch (_) {
          await _invalidate();
          throw SessionExpired();
        }
      });

  Future<Map<String, dynamic>> profile() => _request('GET');
  Future<Map<String, dynamic>> updateProfile(
          String name, String language, int version) =>
      _request('PATCH', {
        'displayName': name,
        'preferredLanguage': language,
        'version': version
      });

  Future<Map<String, dynamic>> _request(String method,
      [Map<String, dynamic>? body]) async {
    final access = await accessToken();
    final request = http.Request(method, apiBase.resolve('me'));
    request.headers.addAll(
        {'Authorization': '***', 'Accept': 'application/json'});
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final response = await http.Response.fromStream(
        await _client.send(request).timeout(const Duration(seconds: 15)));
    if (response.statusCode == 401) {
      await _exclusive(() async {
        if (_tokens?.access == access) await _invalidate();
      });
      throw SessionExpired();
    }
    if (response.statusCode != 200) {
      throw IdentityApiError(response.statusCode);
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
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
