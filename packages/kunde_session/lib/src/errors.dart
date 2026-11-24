/// Failure of the token-session core. Adapters map these to their own, role-specific error types.
sealed class SessionFailure implements Exception {
  const SessionFailure();
}

/// There is no session (nothing stored and nothing in memory).
class SessionMissing extends SessionFailure {
  const SessionMissing();
  @override
  String toString() => 'SessionMissing';
}

/// The server (or the stored state) no longer accepts the session: it has been cleared, sign in again.
class SessionRejected extends SessionFailure {
  const SessionRejected([this.cause]);

  /// The adapter's own error, if any. Never contains tokens.
  final Object? cause;
  @override
  String toString() => 'SessionRejected';
}

/// A transient failure (network, timeout, 5xx): the session is kept and the call can be retried.
class SessionUnavailable extends SessionFailure {
  const SessionUnavailable([this.cause]);

  /// The adapter's own error, if any. Never contains tokens.
  final Object? cause;
  @override
  String toString() => 'SessionUnavailable';
}
