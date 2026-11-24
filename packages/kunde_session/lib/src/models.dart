/// Tokens handed out by a login or a refresh. [extras] carries adapter data stored with the session
/// (for example the OIDC id token or the chosen partner); values are persisted as is.
class IssuedTokens {
  const IssuedTokens({
    required this.access,
    required this.refresh,
    required this.expires,
    this.extras = const {},
  });

  final String access;
  final String refresh;
  final DateTime expires;
  final Map<String, String> extras;

  /// Tokens are secrets: they never appear in logs or error text.
  @override
  String toString() => 'IssuedTokens(<redacted>)';
}

/// What is persisted between launches: the refresh token and the adapter's extras. The short-lived access token
/// is kept in memory only.
class StoredSession {
  const StoredSession(this.refresh, [this.extras = const {}]);

  final String refresh;
  final Map<String, String> extras;

  @override
  String toString() => 'StoredSession(<redacted>)';
}
