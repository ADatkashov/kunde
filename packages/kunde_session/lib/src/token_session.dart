import 'dart:async';

import 'package:flutter/foundation.dart';

import 'errors.dart';
import 'models.dart';
import 'ports.dart';

/// The shared lifecycle of a token session: restore, sign in, access token with automatic refresh, concurrency
/// control, expiry, sign out. It knows nothing about roles, endpoints or stored formats; each app role supplies a
/// [SessionPersistence] and a [TokenRefresher] (its own adapter) and keeps its own authorization logic.
///
/// All state changes run one at a time, so concurrent callers that find an expired access token share a single
/// refresh and never spend a rotating refresh token twice.
class TokenSession extends ChangeNotifier {
  TokenSession({
    required SessionPersistence persistence,
    required TokenRefresher refresher,
    this.leeway = const Duration(seconds: 30),
    this.carryExtrasAcrossSignIn = false,
    DateTime Function()? clock,
  })  : _persistence = persistence,
        _refresher = refresher,
        _clock = clock ?? DateTime.now;

  final SessionPersistence _persistence;
  final TokenRefresher _refresher;
  final DateTime Function() _clock;

  /// An access token expiring within this window is refreshed before use.
  final Duration leeway;

  /// Whether a new sign-in keeps the stored extras of the previous session (the Partner keeps its chosen partner).
  final bool carryExtrasAcrossSignIn;

  /// Called once each time the session expires because the server (or the stored state) rejected it.
  void Function()? onExpired;

  Future<void> _tail = Future.value();
  IssuedTokens? _current;
  Map<String, String> _extras = const {};
  bool _expired = false;

  bool get authenticated => _current != null;

  /// The session ended because it was rejected (not by an explicit sign out).
  bool get expired => _expired;

  int _pending = 0;

  Future<T> _exclusive<T>(Future<T> Function() operation) {
    _pending++;
    final result = _tail.then((_) => operation());
    _tail = result
        .then<void>((_) {}, onError: (Object _, StackTrace __) {})
        .whenComplete(() => _pending--);
    return result;
  }

  bool _fresh(IssuedTokens tokens) =>
      tokens.expires.isAfter(_clock().add(leeway));

  Future<void> _store(IssuedTokens tokens, Map<String, String> extras) async {
    await _persistence.save(StoredSession(tokens.refresh, extras));
    _current = tokens;
    _extras = extras;
    _expired = false;
    notifyListeners();
  }

  Future<void> _discard({required bool markExpired}) async {
    _current = null;
    _extras = const {};
    _expired = markExpired;
    notifyListeners();
    await _persistence.clear();
    if (markExpired) onExpired?.call();
  }

  /// Loads the stored session and refreshes it now. Returns without a session when nothing is stored or the server
  /// rejected it (then [expired] is true). A transient failure is thrown as [SessionUnavailable] and keeps the
  /// stored session for a retry.
  Future<void> restore() => _exclusive(() async {
        final StoredSession? stored;
        try {
          stored = await _persistence.load();
        } on SessionRejected {
          await _discard(markExpired: true);
          return;
        }
        if (stored == null) return;
        try {
          await _refreshFrom(stored.refresh, stored.extras);
        } on SessionRejected {
          // Already cleared and marked expired; restoring simply ends without a session.
        }
      });

  /// Starts a session from tokens obtained by an interactive login (OIDC or phone OTP).
  Future<void> signIn(IssuedTokens tokens) => _exclusive(() async {
        var extras = tokens.extras;
        if (carryExtrasAcrossSignIn) {
          final previous = await _loadQuietly();
          if (previous != null) extras = {...previous.extras, ...extras};
        }
        await _store(tokens, extras);
      });

  /// A valid access token, refreshed first when needed. Throws [SessionMissing] without a session,
  /// [SessionRejected] when the server refused the refresh token (the session is cleared) and
  /// [SessionUnavailable] on a transient failure (the session is kept).
  Future<String> accessToken({bool force = false}) {
    // Fast path: nothing is running and the token is fresh, so no queueing (and no extra async hop) is needed.
    final cached = _current;
    if (!force && _pending == 0 && cached != null && _fresh(cached)) {
      return Future.value(cached.access);
    }
    return _exclusive(() async {
      final current = _current;
      if (current != null && !force && _fresh(current)) return current.access;
      final String refresh;
      final Map<String, String> extras;
      if (current != null) {
        refresh = current.refresh;
        extras = _extras;
      } else {
        final stored = await _loadForRefresh();
        if (stored == null) throw const SessionMissing();
        refresh = stored.refresh;
        extras = stored.extras;
      }
      return (await _refreshFrom(refresh, extras))!;
    });
  }

  Future<StoredSession?> _loadForRefresh() async {
    try {
      return await _persistence.load();
    } on SessionRejected {
      await _discard(markExpired: true);
      throw const SessionRejected();
    }
  }

  Future<StoredSession?> _loadQuietly() async {
    try {
      return await _persistence.load();
    } on SessionRejected {
      return null;
    }
  }

  Future<String?> _refreshFrom(
      String refresh, Map<String, String> extras) async {
    final IssuedTokens issued;
    try {
      issued = await _refresher.refresh(refresh);
    } on SessionRejected {
      await _discard(markExpired: true);
      throw const SessionRejected();
    }
    await _store(issued, {...extras, ...issued.extras});
    return issued.access;
  }

  /// A request using [access] was refused with 401: end the session, unless it has been replaced meanwhile.
  Future<void> rejectIfCurrent(String access) => _exclusive(() async {
        if (_current?.access == access) await _discard(markExpired: true);
      });

  /// Ends the session locally without marking it expired (a failed interactive login).
  Future<void> discard() => _exclusive(() => _discard(markExpired: false));

  /// Reads the stored session without any network call.
  Future<StoredSession?> peek() => _exclusive(_loadQuietly);

  /// Changes extras of the stored session (a null value removes the entry). Does nothing without a session.
  Future<void> updateExtras(Map<String, String?> changes) =>
      _exclusive(() async {
        final stored = _current == null ? await _loadQuietly() : null;
        final refresh = _current?.refresh ?? stored?.refresh;
        if (refresh == null) return;
        final next = {..._current != null ? _extras : stored!.extras};
        changes.forEach((key, value) =>
            value == null ? next.remove(key) : next[key] = value);
        await _persistence.save(StoredSession(refresh, next));
        _extras = next;
      });

  /// Clears the local session first, then lets [revoke] end it on the server. Returns whether the server call
  /// succeeded; the local session is cleared either way.
  Future<bool> signOut(
          {Future<void> Function(StoredSession session)? revoke}) =>
      _exclusive(() async {
        final current = _current;
        final stored = current != null
            ? StoredSession(current.refresh, _extras)
            : await _loadQuietly();
        await _discard(markExpired: false);
        if (stored == null || revoke == null) return true;
        try {
          await revoke(stored);
          return true;
        } catch (_) {
          return false;
        }
      });
}
