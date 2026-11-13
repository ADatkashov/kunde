import 'package:flutter/material.dart';
import '../home/data/kunde_api.dart';
import '../home/presentation/home_screen.dart';
import 'auth_repository.dart';
import 'auth_strings.dart';
import 'consent_panel.dart';
import 'support_panel.dart';
import 'address_panel.dart';

/// Owns the authentication route boundary. Protected content is discarded on expiry.
class AuthScreen extends StatefulWidget {
  const AuthScreen(
      {required this.auth,
      required this.api,
      required this.onLocale,
      super.key});
  final AuthRepository auth;
  final KundeApi api;
  final ValueChanged<Locale> onLocale;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with WidgetsBindingObserver {
  bool _busy = true;
  bool _restorePending = true;
  bool _profileTab = false;
  bool _editing = false;
  bool _conflict = false;
  Map<String, dynamic>? _profile;
  Object? _error;
  String? _notice;
  final _name = TextEditingController();
  final _form = GlobalKey<FormState>();
  String _language = 'ru';
  bool get _dirty =>
      _editing &&
      (_name.text != (_profile?['displayName'] ?? '') ||
          _language !=
              (_profile?['preferredLanguage'] ??
                  Localizations.localeOf(context).languageCode));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.auth.addListener(_authChanged);
    _run(() async {
      await widget.auth.restore();
      _restorePending = false;
      await _load();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        !_busy &&
        widget.auth.authenticated &&
        !_editing) {
      _run(_load);
    }
  }

  void _authChanged() {
    if (!mounted) return;
    if (!widget.auth.authenticated) {
      setState(() {
        _profile = null;
        _editing = false;
        _profileTab = false;
        _name.clear();
      });
    }
  }

  Future<void> _load() async {
    if (!widget.auth.authenticated) return;
    final profile = await widget.auth.profile();
    if (!mounted || !widget.auth.authenticated) return;
    _profile = profile;
    _name.text = profile['displayName'] as String? ?? '';
    _language = profile['preferredLanguage'] as String? ??
        Localizations.localeOf(context).languageCode;
    _conflict = false;
    if (profile['preferredLanguage'] != null) {
      widget.onLocale(Locale(_language));
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) _error = error;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _mayLeave() async {
    if (!_dirty) return true;
    final s = AuthStrings(context);
    return await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
                  title: Text(s.discard),
                  content: Text(s.discardBody),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(s.cancel)),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(s.discardAction)),
                  ],
                )) ??
        false;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    await _run(() async {
      try {
        final profile = await widget.auth.updateProfile(
            _name.text.trim(), _language, _profile!['version'] as int);
        if (!mounted) return;
        _profile = profile;
        _editing = false;
        widget.onLocale(Locale(_language));
        _notice = 'saved';
      } on IdentityApiError catch (error) {
        if (error.status == 409) _conflict = true;
        rethrow;
      }
    });
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
    final colors = Theme.of(context).colorScheme;
    final signedIn = widget.auth.authenticated;
    return PopScope(
      canPop: !_editing,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop && await _mayLeave() && mounted) {
          setState(() => _editing = false);
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('KUNDE'), actions: [
          if (!_editing)
            PopupMenuButton<String>(
              tooltip: s.language,
              icon: const Icon(Icons.language),
              onSelected: (value) => widget.onLocale(Locale(value)),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'ru', child: Text('Русский')),
                PopupMenuItem(value: 'kk', child: Text('Қазақша')),
                PopupMenuItem(value: 'en', child: Text('English'))
              ],
            ),
          if (signedIn)
            TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        if (!await _mayLeave() || !mounted) return;
                        await _run(() async {
                          if (!await widget.auth.logout()) {
                            _notice = 'logoutPartial';
                          }
                        });
                      },
                child: Text(s.logout)),
        ]),
        body: Column(children: [
          if (_error != null || widget.auth.expired || _notice != null)
            Material(
              color: _notice != null
                  ? colors.secondaryContainer
                  : colors.errorContainer,
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(_notice == 'saved'
                        ? s.saved
                        : _notice == 'logoutPartial'
                            ? s.logoutPartial
                            : _message(s)),
                  )),
            ),
          if (_busy) LinearProgressIndicator(semanticsLabel: s.loading),
          Expanded(
              child: _busy && _profile == null
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text('K',
                          style: TextStyle(
                              fontSize: 72, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 24),
                      Text(s.loading),
                    ]))
                  : !signedIn
                      ? _welcome(s)
                      : _profile == null
                          ? Center(
                              child: FilledButton(
                                  onPressed: _busy ? null : () => _run(_load),
                                  child: Text(s.retry)))
                          : _profileTab
                              ? _profileView(s)
                              : HomeScreen(api: widget.api)),
        ]),
        bottomNavigationBar: signedIn && _profile != null
            ? NavigationBar(
                selectedIndex: _profileTab ? 1 : 0,
                onDestinationSelected: _busy
                    ? null
                    : (index) async {
                        if (!await _mayLeave() || !mounted) return;
                        setState(() {
                          _profileTab = index == 1;
                          _editing = false;
                          _error = null;
                          _notice = null;
                        });
                      },
                destinations: [
                  NavigationDestination(
                      icon: const Icon(Icons.home_outlined), label: s.home),
                  NavigationDestination(
                      icon: const Icon(Icons.person_outline), label: s.profile)
                ],
              )
            : null,
      ),
    );
  }

  Widget _welcome(AuthStrings s) => Center(
      child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(28),
            children: [
              Icon(Icons.wb_sunny_outlined,
                  size: 72, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 32),
              Text(s.welcome, style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: 16),
              Text(s.intro),
              const SizedBox(height: 32),
              FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                            await widget.auth.login();
                            await _load();
                          }),
                  child: Text(s.login)),
              if (_restorePending && _error is IdentityUnavailable)
                TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                              await widget.auth.restore();
                              _restorePending = false;
                              await _load();
                            }),
                    child: Text(s.retry)),
              const SizedBox(height: 12),
              OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                            await widget.auth.login(register: true);
                            await _load();
                          }),
                  child: Text(s.register)),
              const SizedBox(height: 20),
              Text(s.browser, style: Theme.of(context).textTheme.bodySmall),
            ],
          )));

  Widget _profileView(AuthStrings s) => Center(
      child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(s.profile, style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: 24),
              if (!_editing) ...[
                CircleAvatar(
                    radius: 36,
                    child: Text(
                        (_profile!['displayName'] as String? ?? 'K')
                                .characters
                                .firstOrNull ??
                            'K',
                        style: const TextStyle(fontSize: 28))),
                const SizedBox(height: 24),
                ListTile(
                    title: Text(s.name),
                    subtitle: Text(_profile!['displayName'] as String? ?? '—')),
                ListTile(
                    title: Text(s.language),
                    subtitle: Text(_profile!['preferredLanguage'] as String? ??
                        Localizations.localeOf(context).languageCode)),
                const SizedBox(height: 24),
                FilledButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _name.text =
                                  _profile!['displayName'] as String? ?? '';
                              _language = _profile!['preferredLanguage']
                                      as String? ??
                                  Localizations.localeOf(context).languageCode;
                              _editing = true;
                            }),
                    child: Text(s.edit)),
                TextButton(
                    onPressed: _busy ? null : () => _run(_load),
                    child: Text(s.reload)),
                const SizedBox(height: 24),
                AddressPanel(auth: widget.auth),
                const SizedBox(height: 24),
                ConsentPanel(auth: widget.auth),
                const SizedBox(height: 24),
                SupportPanel(auth: widget.auth),
              ] else
                Form(
                    key: _form,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                              controller: _name,
                              enabled: !_busy,
                              decoration: InputDecoration(labelText: s.name),
                              maxLength: 80,
                              validator: (value) => value == null ||
                                      value.trim().isEmpty ||
                                      value.runes.length > 80 ||
                                      RegExp(r'[\x00-\x1F\x7F-\x9F\u200B-\u200F\u202A-\u202E\u2060-\u206F\uFEFF]')
                                          .hasMatch(value)
                                  ? s.invalid
                                  : null),
                          const SizedBox(height: 20),
                          Text(s.language),
                          const SizedBox(height: 8),
                          Wrap(
                              spacing: 8,
                              children: ['ru', 'kk', 'en']
                                  .map((code) => ChoiceChip(
                                      label: Text({
                                        'ru': 'Русский',
                                        'kk': 'Қазақша',
                                        'en': 'English'
                                      }[code]!),
                                      selected: _language == code,
                                      onSelected: _busy
                                          ? null
                                          : (_) =>
                                              setState(() => _language = code)))
                                  .toList()),
                          const SizedBox(height: 28),
                          FilledButton(
                              onPressed: _busy || _conflict ? null : _save,
                              child: Text(s.save)),
                          if (_conflict)
                            TextButton(
                                onPressed: _busy
                                    ? null
                                    : () async {
                                        if (await _mayLeave() && mounted) {
                                          await _run(() async {
                                            await _load();
                                            _editing = false;
                                          });
                                        }
                                      },
                                child: Text(s.reload)),
                          TextButton(
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      if (await _mayLeave() && mounted) {
                                        setState(() => _editing = false);
                                      }
                                    },
                              child: Text(s.cancel)),
                        ])),
            ],
          )));

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.auth.removeListener(_authChanged);
    _name.dispose();
    super.dispose();
  }
}
