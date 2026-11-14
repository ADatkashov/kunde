import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_repository.dart';

enum PhoneAuthFailure {
  invalidPhone,
  invalidCode,
  rateLimited,
  unavailable,
  network
}

class PhoneAuthException implements Exception {
  PhoneAuthException(this.failure);
  final PhoneAuthFailure failure;
}

class OtpChallenge {
  const OtpChallenge(this.expiresInSeconds, this.resendAfterSeconds);
  final int expiresInSeconds;
  final int resendAfterSeconds;
}

/// Phone OTP session API (`/auth/otp/request`, `/auth/otp/verify`,
/// `/auth/token/refresh`, `/auth/logout`). Refresh/logout plug into the shared
/// [AuthRepository]; the interactive steps are driven by `PhoneLoginFlow`.
class PhoneAuthGateway implements OAuthGateway, SessionRevoker {
  PhoneAuthGateway(
      {required this.apiBase,
      http.Client? client,
      this.timeout = const Duration(seconds: 20)})
      : _client = client ?? http.Client();
  final Uri apiBase;
  final Duration timeout;
  final http.Client _client;

  Future<http.Response> _post(String path, Map<String, dynamic> body) async {
    try {
      return await _client
          .post(apiBase.resolve(path),
              headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json'
              },
              body: jsonEncode(body))
          .timeout(timeout);
    } on TimeoutException {
      throw PhoneAuthException(PhoneAuthFailure.network);
    } on http.ClientException {
      throw PhoneAuthException(PhoneAuthFailure.network);
    }
  }

  static Map<String, dynamic> _json(http.Response response) {
    try {
      final value = jsonDecode(response.body);
      if (value is Map<String, dynamic>) return value;
    } on FormatException {
      // handled below
    }
    throw PhoneAuthException(PhoneAuthFailure.unavailable);
  }

  Future<OtpChallenge> requestOtp(String phoneE164) async {
    final response = await _post('auth/otp/request', {'phone': phoneE164});
    switch (response.statusCode) {
      case 202:
        final json = _json(response);
        return OtpChallenge((json['expiresInSeconds'] as num?)?.toInt() ?? 300,
            (json['resendAfterSeconds'] as num?)?.toInt() ?? 30);
      case 400:
        throw PhoneAuthException(PhoneAuthFailure.invalidPhone);
      case 429:
        throw PhoneAuthException(PhoneAuthFailure.rateLimited);
      default:
        throw PhoneAuthException(PhoneAuthFailure.unavailable);
    }
  }

  Future<AuthTokens> verifyOtp(String phoneE164, String code) async {
    final response =
        await _post('auth/otp/verify', {'phone': phoneE164, 'code': code});
    switch (response.statusCode) {
      case 200:
        return _tokens(_json(response));
      case 400:
      case 401:
        throw PhoneAuthException(PhoneAuthFailure.invalidCode);
      case 429:
        throw PhoneAuthException(PhoneAuthFailure.rateLimited);
      default:
        throw PhoneAuthException(PhoneAuthFailure.unavailable);
    }
  }

  AuthTokens _tokens(Map<String, dynamic> json) {
    final access = json['accessToken'];
    final refresh = json['refreshToken'];
    final expiresIn = json['expiresIn'];
    if (access is! String ||
        access.isEmpty ||
        refresh is! String ||
        refresh.isEmpty ||
        expiresIn is! num ||
        expiresIn <= 0) {
      throw PhoneAuthException(PhoneAuthFailure.unavailable);
    }
    return AuthTokens(access, refresh, null,
        DateTime.now().add(Duration(seconds: expiresIn.toInt())));
  }

  @override
  Future<AuthTokens> login({bool register = false}) =>
      throw IdentityUnavailable(); // interactive: see PhoneLoginFlow

  @override
  Future<AuthTokens> refresh(String refreshToken) async {
    final http.Response response;
    try {
      response =
          await _post('auth/token/refresh', {'refreshToken': refreshToken});
    } on PhoneAuthException {
      throw IdentityUnavailable();
    }
    if (response.statusCode == 200) {
      try {
        return _tokens(_json(response));
      } on PhoneAuthException {
        throw IdentityUnavailable();
      }
    }
    if (response.statusCode == 400 || response.statusCode == 401) {
      throw SessionExpired();
    }
    throw IdentityUnavailable();
  }

  @override
  Future<void> revoke(String refreshToken) async {
    final http.Response response;
    try {
      response = await _post('auth/logout', {'refreshToken': refreshToken});
    } on PhoneAuthException {
      throw IdentityUnavailable();
    }
    if (response.statusCode != 204) throw IdentityUnavailable();
  }

  @override
  Future<void> logout(String? idToken) async {}
}
