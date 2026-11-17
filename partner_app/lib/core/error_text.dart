import '../data/errors.dart';
import 'strings.dart';

/// Human text for any failure; never exposes status codes, JSON or traces.
String errorText(S s, Object error) {
  if (error is PartnerApiException) {
    switch (error.code) {
      case 'SCHEDULE_CONFLICT':
        return s.errScheduleConflict;
      case 'ORDER_TRANSITION_INVALID':
      case 'BOOKING_TRANSITION_INVALID':
        return s.errConflict;
      case 'REASON_REQUIRED':
        return s.errValidation;
      case 'PARTNER_ROLE_FORBIDDEN':
        return s.errForbidden;
    }
    switch (error.kind) {
      case ApiErrorKind.network:
        return s.errNetworkBody;
      case ApiErrorKind.timeout:
        return s.errTimeout;
      case ApiErrorKind.unauthorized:
        return s.sessionExpired;
      case ApiErrorKind.forbidden:
        return s.errForbidden;
      case ApiErrorKind.notFound:
        return s.errNotFound;
      case ApiErrorKind.conflict:
        return s.errConflict;
      case ApiErrorKind.validation:
        return s.errValidation;
      case ApiErrorKind.server:
        return s.errServer;
      case ApiErrorKind.unknown:
        return s.errUnknown;
    }
  }
  if (error is PartnerAuthException) {
    switch (error.code) {
      case PartnerAuthException.invalidApiBase:
        return s.apiNotConfigured;
      case PartnerAuthException.network:
        return s.errNetworkBody;
      case PartnerAuthException.timeout:
        return s.errTimeout;
      case PartnerAuthException.rateLimited:
        return s.tooManyAttempts;
      case PartnerAuthException.wrongCode:
        return s.wrongCode;
      default:
        return s.errUnknown;
    }
  }
  if (error is SessionExpiredException) return s.sessionExpired;
  return s.errUnknown;
}

/// True for failures caused by connectivity (worth a calm "offline" state).
bool isOffline(Object error) =>
    error is PartnerApiException &&
        (error.kind == ApiErrorKind.network ||
            error.kind == ApiErrorKind.timeout) ||
    error is PartnerAuthException &&
        (error.code == PartnerAuthException.network ||
            error.code == PartnerAuthException.timeout);
