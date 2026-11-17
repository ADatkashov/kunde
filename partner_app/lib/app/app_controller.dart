import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../auth/partner_session.dart';
import '../data/errors.dart';
import '../data/models.dart';
import '../data/partner_api.dart';
import '../data/partner_operations.dart';
import 'ops_store.dart';

enum AppPhase {
  /// Looking for a stored session.
  booting,
  signedOut,

  /// A stored session exists but the server could not be reached.
  unreachable,
  choosingPartner,

  /// Signed in but no approved partner is linked to the account.
  noAccess,
  ready,
}

/// Why the user was sent back to the login screen.
enum SignOutNotice { sessionExpired, accessRevoked }

/// Owns authentication, partner discovery/selection and the per-partner
/// [OpsStore]. All access decisions come from the server; this class only
/// reacts to them.
class AppController extends ChangeNotifier {
  AppController({
    required this.session,
    http.Client? client,
    this.pollInterval = const Duration(seconds: 20),
    this.retryDelay = const Duration(milliseconds: 600),
  }) : _client = client {
    session.onExpired = _onSessionExpired;
  }

  final PartnerSession session;
  final http.Client? _client;
  final Duration? pollInterval;
  final Duration retryDelay;

  AppPhase _phase = AppPhase.booting;
  List<PartnerMembership> _partners = const [];
  PartnerMembership? _partner;
  PartnerApi? _api;
  OpsStore? _store;
  SignOutNotice? _notice;
  bool _disposed = false;

  AppPhase get phase => _phase;
  List<PartnerMembership> get partners => _partners;
  PartnerMembership? get partner => _partner;
  OpsStore? get store => _store;
  PartnerApi? get api => _api;
  SignOutNotice? get notice => _notice;
  bool get apiConfigured => session.baseIsValid;

  void _set(AppPhase phase) {
    _phase = phase;
    if (!_disposed) notifyListeners();
  }

  PartnerApi _newApi() => PartnerApi(
        baseUri: session.apiBase,
        accessToken: session.accessToken,
        forceRefresh: () => session.accessToken(force: true),
        client: _client,
        retryDelay: retryDelay,
      );

  /// Restores a stored session after an app restart.
  Future<void> bootstrap() async {
    if (!session.baseIsValid || !await session.hasStoredSession()) {
      _set(AppPhase.signedOut);
      return;
    }
    _set(AppPhase.booting);
    await _discover(restore: true);
  }

  Future<void> requestOtp(String phone) => session.requestOtp(phone);

  Future<void> verifyOtp(String phone, String code) async {
    await session.verifyOtp(phone, code);
    _notice = null;
    await _discover(restore: false, throwOnFailure: true);
  }

  Future<void> _discover(
      {required bool restore, bool throwOnFailure = false}) async {
    _teardownPartner();
    _api?.close();
    final api = _api = _newApi();
    try {
      final rows = await api.getList('partner/partners');
      final approved = rows
          .map(PartnerMembership.fromJson)
          .where((p) => p.approved)
          .toList();
      _partners = approved;
      if (approved.isEmpty) {
        _set(AppPhase.noAccess);
        return;
      }
      PartnerMembership? pick;
      if (approved.length == 1) {
        pick = approved.first;
      } else if (restore) {
        final saved = await session.storedPartnerId();
        for (final p in approved) {
          if (p.id == saved) pick = p;
        }
      }
      if (pick == null) {
        _set(AppPhase.choosingPartner);
      } else {
        await select(pick);
      }
    } on SessionExpiredException {
      // _onSessionExpired already moved us to the login screen.
      if (throwOnFailure) rethrow;
    } on PartnerApiException catch (e) {
      if (e.kind == ApiErrorKind.unauthorized) {
        await _expire();
        if (throwOnFailure) rethrow;
        return;
      }
      if (restore &&
          (e.kind == ApiErrorKind.network ||
              e.kind == ApiErrorKind.timeout ||
              e.kind == ApiErrorKind.server)) {
        _set(AppPhase.unreachable);
        return;
      }
      if (e.kind == ApiErrorKind.forbidden) {
        // Signed in but without partner permissions: show the calm
        // "no access" screen (the server remains the authority).
        _partners = const [];
        _set(AppPhase.noAccess);
        return;
      }
      await session.logout();
      _set(AppPhase.signedOut);
      if (throwOnFailure) rethrow;
    } on PartnerAuthException {
      if (restore) {
        _set(AppPhase.unreachable);
        return;
      }
      rethrow;
    } on FormatException {
      await session.logout();
      _set(AppPhase.signedOut);
      if (throwOnFailure) rethrow;
    }
  }

  Future<void> retryRestore() async {
    _set(AppPhase.booting);
    await _discover(restore: true);
  }

  /// Opens the workspace of [p]. The first protected call is made by the data
  /// screens; the server rejects anyone without an APPROVED membership.
  Future<void> select(PartnerMembership p) async {
    _teardownPartner();
    _partner = p;
    final api = _api ??= _newApi();
    final store = _store = OpsStore(
      PartnerOperations(api, p.id),
      onFatal: _onFatal,
      pollInterval: pollInterval,
    );
    await session.rememberPartner(p.id);
    _set(AppPhase.ready);
    unawaited(store.refreshAll().then((_) => store.startPolling()));
  }

  /// Back to the partner list (only offered when there are several).
  void switchPartner() {
    _teardownPartner();
    _set(_partners.length > 1 ? AppPhase.choosingPartner : AppPhase.ready);
  }

  void _teardownPartner() {
    _store?.dispose();
    _store = null;
    _partner = null;
  }

  void _onFatal(Object error) {
    if (_phase != AppPhase.ready) return;
    if (error is SessionExpiredException ||
        (error is PartnerApiException &&
            error.kind == ApiErrorKind.unauthorized)) {
      unawaited(_expire());
    } else if (error is PartnerApiException && error.isAccessRevoked) {
      unawaited(_revoked());
    }
  }

  void _onSessionExpired() {
    if (_phase == AppPhase.signedOut) return;
    _notice = SignOutNotice.sessionExpired;
    _teardownPartner();
    _api?.close();
    _api = null;
    _set(AppPhase.signedOut);
  }

  Future<void> _expire() async {
    await session.clear();
    _onSessionExpired();
  }

  /// The server no longer knows this staff membership: re-read the list so the
  /// user lands on another business or on the "no access" screen.
  Future<void> _revoked() async {
    _notice = SignOutNotice.accessRevoked;
    await session.rememberPartner(null);
    await _discover(restore: false);
  }

  void clearNotice() {
    _notice = null;
    if (!_disposed) notifyListeners();
  }

  Future<void> logout() async {
    _teardownPartner();
    _api?.close();
    _api = null;
    _notice = null;
    await session.logout();
    _partners = const [];
    _set(AppPhase.signedOut);
  }

  @override
  void dispose() {
    _disposed = true;
    _teardownPartner();
    _api?.close();
    session.dispose();
    super.dispose();
  }
}
