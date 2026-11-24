/// Why a request failed, independent of HTTP details.
enum ApiErrorKind {
  network,
  timeout,
  unauthorized,
  forbidden,
  notFound,
  conflict,
  validation,
  server,
  unknown,
}

/// Failure of an authenticated Partner API call. [code] is the backend error
/// code (e.g. `ORDER_TRANSITION_INVALID`) when the server supplied one.
class PartnerApiException implements Exception {
  const PartnerApiException(this.statusCode, this.message,
      {this.code, ApiErrorKind? kind})
      : _kind = kind;

  final int statusCode;
  final String message;
  final String? code;
  final ApiErrorKind? _kind;

  ApiErrorKind get kind {
    final explicit = _kind;
    if (explicit != null) return explicit;
    if (statusCode == 401) return ApiErrorKind.unauthorized;
    if (statusCode == 403) return ApiErrorKind.forbidden;
    if (statusCode == 404) return ApiErrorKind.notFound;
    if (statusCode == 409) return ApiErrorKind.conflict;
    if (statusCode == 400 || statusCode == 422) return ApiErrorKind.validation;
    if (statusCode >= 500) return ApiErrorKind.server;
    return ApiErrorKind.unknown;
  }

  /// The signed-in staff member lost access to this partner.
  bool get isAccessRevoked =>
      code == 'PARTNER_NOT_FOUND' ||
      code == 'PARTNER_NOT_APPROVED' ||
      (kind == ApiErrorKind.notFound && code == null);

  @override
  String toString() => 'PartnerApiException($statusCode, $code)';
}

/// Failure of the OTP / token endpoints.
class PartnerAuthException implements Exception {
  const PartnerAuthException(this.code);
  final String code;

  static const invalidApiBase = 'INVALID_API_BASE';
  static const network = 'NETWORK';
  static const timeout = 'TIMEOUT';
  static const invalidResponse = 'INVALID_RESPONSE';
  static const rejected = 'REJECTED';
  static const rateLimited = 'RATE_LIMITED';
  static const wrongCode = 'WRONG_CODE';

  @override
  String toString() => 'PartnerAuthException($code)';
}

/// The stored session can no longer be refreshed: the user must sign in again.
class SessionExpiredException implements Exception {
  const SessionExpiredException();
  @override
  String toString() => 'SessionExpiredException';
}
