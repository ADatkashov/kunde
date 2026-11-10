import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const _issuer = String.fromEnvironment('OIDC_ISSUER');
const _clientId = String.fromEnvironment('OIDC_CLIENT_ID');
const _redirectUri = String.fromEnvironment(
  'OIDC_REDIRECT_URI',
  defaultValue: 'com.kunde.mobile:/oauth2redirect',
);
const _scopesRaw = String.fromEnvironment(
  'OIDC_SCOPES',
  defaultValue: 'openid profile email offline_access kunde.poc',
);
const _apiUrl = String.fromEnvironment(
  'IDENTITY_POC_API_URL',
  defaultValue: 'http://10.0.2.2:8080/api/v1/poc/whoami',
);

class IdentityPocScreen extends StatefulWidget {
  const IdentityPocScreen({super.key});

  @override
  State<IdentityPocScreen> createState() => _IdentityPocScreenState();
}

class _IdentityPocScreenState extends State<IdentityPocScreen> {
  static const _storage = FlutterSecureStorage();
  static const _appAuth = FlutterAppAuth();
  static const _refreshTokenKey = 'identity_poc.refresh_token';
  static const _idTokenKey = 'identity_poc.id_token';

  String? _accessToken;
  String _status = 'Not signed in';
  String? _apiResult;
  bool _busy = false;
  List<String> get _scopes => _scopesRaw.split(RegExp(r'\s+'));
  bool get _allowInsecureConnections {
    final issuer = Uri.tryParse(_issuer);
    final host = issuer?.host.toLowerCase();
    return issuer?.scheme == 'http' && host != null &&
        (host == 'localhost' || host.endsWith('.localhost') ||
            host == '127.0.0.1' || host == '::1');
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _apiResult = null;
    });
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = 'Operation failed (${error.runtimeType}). Check local IdP configuration.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _login() => _run(() async {
        _requireConfig();
        final response = await _appAuth.authorizeAndExchangeCode(
          AuthorizationTokenRequest(
            _clientId,
            _redirectUri,
            issuer: _issuer,
            scopes: _scopes,
            allowInsecureConnections: _allowInsecureConnections,
          ),
        );
        final accessToken = response.accessToken;
        if (accessToken == null) throw StateError('No access token returned');
        _accessToken = accessToken;
        final refreshToken = response.refreshToken;
        if (refreshToken != null) await _storage.write(key: _refreshTokenKey, value: refreshToken);
        final idToken = response.idToken;
        if (idToken != null) await _storage.write(key: _idTokenKey, value: idToken);
        if (!mounted) return;
        setState(() => _status = 'Authorization Code + PKCE completed');
      });

  Future<void> _refresh() => _run(() async {
        _requireConfig();
        final refreshToken = await _storage.read(key: _refreshTokenKey);
        if (refreshToken == null) throw StateError('No saved refresh token');
        final response = await _appAuth.token(
          TokenRequest(
            _clientId,
            _redirectUri,
            issuer: _issuer,
            refreshToken: refreshToken,
            scopes: _scopes,
            allowInsecureConnections: _allowInsecureConnections,
          ),
        );
        final accessToken = response.accessToken;
        if (accessToken == null) throw StateError('Refresh returned no access token');
        _accessToken = accessToken;
        final rotated = response.refreshToken;
        if (rotated != null) await _storage.write(key: _refreshTokenKey, value: rotated);
        final idToken = response.idToken;
        if (idToken != null) await _storage.write(key: _idTokenKey, value: idToken);
        if (!mounted) return;
        setState(() => _status = 'Refresh completed');
      });

  Future<void> _callApi() => _run(() async {
        final token = _accessToken;
        if (token == null) throw StateError('Sign in first');
        final response = await http.get(
          Uri.parse(_apiUrl),
          headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
        );
        if (!mounted) return;
        setState(() {
          _status = 'API returned HTTP ${response.statusCode}';
          _apiResult = const JsonEncoder.withIndent('  ').convert(jsonDecode(response.body));
        });
      });

  Future<void> _logout() => _run(() async {
        _requireConfig();
        final idToken = await _storage.read(key: _idTokenKey);
        try {
          if (idToken != null) {
            await _appAuth.endSession(
              EndSessionRequest(
                idTokenHint: idToken,
                postLogoutRedirectUrl: _redirectUri,
                issuer: _issuer,
                allowInsecureConnections: _allowInsecureConnections,
              ),
            );
          }
        } finally {
          await _storage.delete(key: _refreshTokenKey);
          await _storage.delete(key: _idTokenKey);
          _accessToken = null;
        }
        if (!mounted) return;
        setState(() => _status = 'Local tokens cleared; provider logout requested');
      });

  void _requireConfig() {
    if (_issuer.isEmpty || _clientId.isEmpty) {
      throw StateError('OIDC_ISSUER and OIDC_CLIENT_ID are required');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('KUNDE Identity POC')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('Provider: ${_issuer.isEmpty ? 'not configured' : Uri.parse(_issuer).host}'),
              const SizedBox(height: 8),
              const Text('Local test only. Use a synthetic account. No token values are shown.'),
              const SizedBox(height: 16),
              Text(_status),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _login,
                child: const Text('Sign in with system browser'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : _refresh,
                child: const Text('Refresh session'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : _callApi,
                child: const Text('Call protected KUNDE API'),
              ),
              TextButton(
                onPressed: _busy ? null : _logout,
                child: const Text('Log out'),
              ),
              if (_busy) const LinearProgressIndicator(),
              if (_apiResult != null) ...[
                const SizedBox(height: 24),
                SelectableText(_apiResult!, style: const TextStyle(fontFamily: 'monospace')),
              ],
            ],
          ),
        ),
      );
}
