import 'package:flutter/material.dart';

import 'package:kunde_auth/auth_repository.dart';
import 'package:kunde_auth/auth_strings.dart';
import 'package:kunde_auth/phone_auth_gateway.dart';
import 'package:kunde_auth/phone_login_flow.dart';

/// Authentication boundary of the operator apps (Executor, Admin): phone login, session restore, profile check and
/// session expiry. It knows nothing about the consumer shell, so those apps do not compile consumer features.
/// Protected content is built only for a signed-in user whose profile loaded, and is discarded when the session ends.
class OperatorGate extends StatefulWidget {
  const OperatorGate({
    required this.auth,
    required this.onLocale,
    required this.authorizedHome,
    this.devOtpHint = false,
    super.key,
  });

  final AuthRepository auth;
  final ValueChanged<Locale> onLocale;
  final WidgetBuilder authorizedHome;
  final bool devOtpHint;

  @override
  State<OperatorGate> createState() => _OperatorGateState();
}

class _OperatorGateState extends State<OperatorGate> {
  bool _busy = true;
  bool _profileLoaded = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    widget.auth.addListener(_authChanged);
    _run(() async {
      await widget.auth.restore();
      await _load();
    });
  }

  @override
  void dispose() {
    widget.auth.removeListener(_authChanged);
    super.dispose();
  }

  void _authChanged() {
    if (!mounted) return;
    if (!widget.auth.authenticated) {
      setState(() => _profileLoaded = false);
    }
  }

  Future<void> _load() async {
    if (!widget.auth.authenticated) return;
    final profile = await widget.auth.profile();
    if (!mounted || !widget.auth.authenticated) return;
    _profileLoaded = true;
    final language = profile['preferredLanguage'] as String?;
    if (language != null) widget.onLocale(Locale(language));
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) _error = error;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _message(AuthStrings s) {
    if (_error is SessionExpired || widget.auth.expired) return s.expired;
    final error = _error;
    if (error is IdentityApiError) {
      if (error.status == 403) return s.denied;
      if (error.status == 409) return s.conflict;
      if (error.status == 400) return s.invalid;
      return s.offline;
    }
    return error is IdentityUnavailable ? s.offline : s.loginFailed;
  }

  @override
  Widget build(BuildContext context) {
    final s = AuthStrings(context);
    final signedIn = widget.auth.authenticated;
    if (signedIn && _profileLoaded) {
      return widget.authorizedHome(context);
    }
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('KUNDE'),
        actions: [
          PopupMenuButton<String>(
            tooltip: s.language,
            icon: const Icon(Icons.language),
            onSelected: (value) => widget.onLocale(Locale(value)),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'ru', child: Text('Русский')),
              PopupMenuItem(value: 'kk', child: Text('Қазақша')),
              PopupMenuItem(value: 'en', child: Text('English')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_error != null || widget.auth.expired)
              Material(
                color: colors.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(_message(s)),
                  ),
                ),
              ),
            if (_busy) LinearProgressIndicator(semanticsLabel: s.loading),
            Expanded(child: _body(s)),
          ],
        ),
      ),
    );
  }

  Widget _body(AuthStrings s) {
    if (_busy && !_profileLoaded) {
      return Center(child: Text(s.loading));
    }
    if (!widget.auth.authenticated) {
      final gateway = widget.auth.gateway;
      if (gateway is PhoneAuthGateway) {
        return PhoneLoginFlow(
          gateway: gateway,
          devOtpHint: widget.devOtpHint,
          onSignedIn: (tokens) async {
            await widget.auth.signIn(tokens);
            _error = null;
            if (mounted) setState(() => _busy = true);
            try {
              await _load();
            } catch (error) {
              if (mounted) _error = error;
            } finally {
              if (mounted) setState(() => _busy = false);
            }
          },
        );
      }
      return Center(child: Text(s.offline));
    }
    return Center(
      child: FilledButton(
        onPressed: _busy ? null : () => _run(_load),
        child: Text(s.retry),
      ),
    );
  }
}
