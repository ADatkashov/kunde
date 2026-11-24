import 'models.dart';

/// Where a session lives between launches. Each adapter supplies its own storage key and stored format, so
/// sessions of different roles/apps never read each other's data. [load] returns null when nothing usable is
/// stored (and may discard unreadable state itself) and throws [SessionRejected] when the stored state belongs to
/// a different context and must expire the session.
abstract interface class SessionPersistence {
  Future<StoredSession?> load();
  Future<void> save(StoredSession session);
  Future<void> clear();
}

/// The role-specific network step that exchanges a refresh token for new tokens (the backend rotates the refresh
/// token on every use). It throws [SessionRejected] when the server refuses the token and [SessionUnavailable] on a
/// transient failure; anything else is propagated unchanged and keeps the session.
abstract interface class TokenRefresher {
  Future<IssuedTokens> refresh(String refreshToken);
}
