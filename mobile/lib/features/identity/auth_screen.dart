import 'package:flutter/material.dart';

import '../../core/localization/kunde_localizations.dart';
import '../home/presentation/home_strings.dart';
import '../auto/auto_services.dart';
import '../leisure/leisure_services.dart';
import '../booking/booking_services.dart';
import '../booking/presentation/orders_hub.dart';
import '../food/food_services.dart';
import '../education/education_enrollment_screen.dart';
import '../food/presentation/orders_tab.dart';
import '../home/data/kunde_api.dart';
import '../home/presentation/home_screen.dart';
import '../shell/tabs.dart';
import '../assistant/assistant_screen.dart';
import 'auth_repository.dart';
import 'auth_strings.dart';
import 'consent_panel.dart';
import '../delivery/delivery_api.dart';
import '../rides/ride_api.dart';
import 'phone_auth_gateway.dart';
import 'phone_login_flow.dart';
import '../partner/partner_panel.dart';
import 'support_panel.dart';
import 'address_panel.dart';

/// Owns the authentication route boundary. Protected content is discarded on expiry.
class AuthScreen extends StatefulWidget {
  const AuthScreen({
    required this.auth,
    required this.api,
    required this.onLocale,
    this.onTheme,
    this.devOtpHint = false,
    this.partnerEnabled = false,
    this.partnerApplyEnabled = true,
    this.food,
    this.booking,
    this.auto,
    this.leisure,
    this.authorizedHome,
    super.key,
  });
  final AuthRepository auth;
  final WidgetBuilder? authorizedHome;
  final KundeApi api;
  final ValueChanged<Locale> onLocale;
  final ValueChanged<ThemeMode>? onTheme;
  final bool devOtpHint;

  /// Partner onboarding and offerings (ADR-018); off unless the build enables it.
  final bool partnerEnabled;
  final bool partnerApplyEnabled;

  /// KUNDE Food (restaurants, cart, orders); shown when the server enables the marketplace.
  final FoodServices? food;

  /// Service booking (barbershops); shown when the server enables it.
  final BookingServices? booking;
  final AutoServices? auto;
  final LeisureServices? leisure;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with WidgetsBindingObserver {
  bool _busy = true;
  bool _restorePending = true;
  KundeTab _tab = KundeTab.home;
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
        _tab = KundeTab.home;
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
                child: Text(s.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(s.discardAction),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    await _run(() async {
      try {
        final profile = await widget.auth.updateProfile(
          _name.text.trim(),
          _language,
          _profile!['version'] as int,
        );
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
        appBar: signedIn && _profile != null && _tab != KundeTab.profile
            ? null
            : AppBar(
                title: Text(signedIn && _profile != null ? s.profile : 'KUNDE'),
                actions: [
                  if (!_editing)
                    if (!signedIn || _profile == null) _languageMenu(s),
                  if (signedIn)
                    if (_profile == null || _editing)
                      TextButton(
                        onPressed: _busy ? null : _logout,
                        child: Text(s.logout),
                      ),
                ],
              ),
        body: SafeArea(
          child: Column(
            children: [
              if (_error != null || widget.auth.expired || _notice != null)
                Material(
                  color: _notice != null
                      ? colors.secondaryContainer
                      : colors.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _notice == 'saved'
                            ? s.saved
                            : _notice == 'logoutPartial'
                                ? s.logoutPartial
                                : _notice == 'logoutPartialPhone'
                                    ? s.logoutPartialPhone
                                    : _message(s),
                      ),
                    ),
                  ),
                ),
              if (_busy) LinearProgressIndicator(semanticsLabel: s.loading),
              Expanded(
                child: _busy && _profile == null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'K',
                              style: TextStyle(
                                fontSize: 72,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(s.loading),
                          ],
                        ),
                      )
                    : !signedIn
                        ? _welcome(s)
                        : _profile == null
                            ? Center(
                                child: FilledButton(
                                  onPressed: _busy ? null : () => _run(_load),
                                  child: Text(s.retry),
                                ),
                              )
                            : widget.authorizedHome?.call(context) ??
                                switch (_tab) {
                                  KundeTab.profile => _profileView(s),
                                  KundeTab.search => SearchTab(
                                      api: widget.api,
                                      food: widget.food,
                                      booking: widget.booking,
                                    ),
                                  KundeTab.assistant => const AssistantScreen(),
                                  KundeTab.orders => widget.food != null &&
                                          widget.booking != null
                                      ? OrdersHubTab(
                                          food: widget.food!,
                                          booking: widget.booking!,
                                        )
                                      : widget.food != null
                                          ? FoodOrdersTab(
                                              services: widget.food!)
                                          : const OrdersTab(),
                                  KundeTab.home => HomeScreen(
                                      api: widget.api,
                                      rides: RideApi(widget.auth),
                                      delivery: DeliveryApi(widget.auth),
                                      food: widget.food,
                                      booking: widget.booking,
                                      auto: widget.auto,
                                      leisure: widget.leisure,
                                      educationAuth: widget.auth,
                                      onOpenAssistant: () => setState(
                                          () => _tab = KundeTab.assistant),
                                      onOpenSearch: () => setState(
                                          () => _tab = KundeTab.search),
                                      onOpenOrders: () => setState(
                                          () => _tab = KundeTab.orders),
                                    ),
                                },
              ),
            ],
          ),
        ),
        bottomNavigationBar:
            signedIn && _profile != null && widget.authorizedHome == null
                ? KundeNavigationBar(
                    selected: _tab,
                    onSelected: _busy
                        ? null
                        : (tab) async {
                            if (!await _mayLeave() || !mounted) return;
                            setState(() {
                              _tab = tab;
                              _editing = false;
                              _error = null;
                              _notice = null;
                            });
                          },
                  )
                : null,
      ),
    );
  }

  Widget _welcome(AuthStrings s) {
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
    return _oidcWelcome(s);
  }

  Widget _oidcWelcome(AuthStrings s) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(28),
            children: [
              Icon(
                Icons.wb_sunny_outlined,
                size: 72,
                color: Theme.of(context).colorScheme.primary,
              ),
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
                child: Text(s.login),
              ),
              if (_restorePending && _error is IdentityUnavailable)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                            await widget.auth.restore();
                            _restorePending = false;
                            await _load();
                          }),
                  child: Text(s.retry),
                ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                          await widget.auth.login(register: true);
                          await _load();
                        }),
                child: Text(s.register),
              ),
              const SizedBox(height: 20),
              Text(s.browser, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      );

  Future<void> _logout() async {
    if (!await _mayLeave() || !mounted) return;
    await _run(() async {
      if (!await widget.auth.logout()) {
        _notice =
            widget.auth.usesPhoneOtp ? 'logoutPartialPhone' : 'logoutPartial';
      }
    });
  }

  Widget _languageMenu(AuthStrings s, {Widget? child}) =>
      PopupMenuButton<String>(
        tooltip: s.language,
        icon: child == null ? const Icon(Icons.language) : null,
        onSelected: (value) => widget.onLocale(Locale(value)),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'ru', child: Text('Русский')),
          PopupMenuItem(value: 'kk', child: Text('Қазақша')),
          PopupMenuItem(value: 'en', child: Text('English')),
        ],
        child: child,
      );

  Widget _profileView(AuthStrings s) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (!_editing) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF5E36A5), Color(0xFF33265F)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: const Color(0xFFF2C77D),
                        foregroundColor: const Color(0xFF101426),
                        child: Text(
                          (_profile!['displayName'] as String?)
                                  ?.characters
                                  .firstOrNull ??
                              'K',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _profile!['displayName'] as String? ??
                              s.unnamedProfile,
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
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
                  child: Text(s.edit),
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.place_outlined),
                    title: Text(s.addresses),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (context) => Scaffold(
                          appBar: AppBar(title: Text(s.addresses)),
                          body: SafeArea(
                            child: ListView(
                              padding: const EdgeInsets.all(16),
                              children: [AddressPanel(auth: widget.auth)],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Card(
                  child: _languageMenu(
                    s,
                    child: ListTile(
                      leading: const Icon(Icons.language_rounded),
                      title: Text(s.language),
                      trailing: Text(Localizations.localeOf(context)
                          .languageCode
                          .toUpperCase()),
                    ),
                  ),
                ),
                if (widget.onTheme != null)
                  Card(
                    child: SwitchListTile(
                      secondary: const Icon(Icons.palette_outlined),
                      title: Text(KundeLocalizations.of(context).appearance),
                      subtitle: Text(
                        Theme.of(context).brightness == Brightness.dark
                            ? KundeLocalizations.of(context).darkAppearance
                            : KundeLocalizations.of(context).lightAppearance,
                      ),
                      value: Theme.of(context).brightness == Brightness.dark,
                      onChanged: (dark) => widget
                          .onTheme!(dark ? ThemeMode.dark : ThemeMode.light),
                    ),
                  ),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.shield_outlined),
                    title: Text(s.security),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(s.security),
                        content: Text(widget.auth.usesPhoneOtp
                            ? s.phoneSecurity
                            : s.browser),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(MaterialLocalizations.of(context)
                                .okButtonLabel),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Card(
                  child: ListTile(
                    leading: Icon(Icons.logout_rounded,
                        color: Theme.of(context).colorScheme.error),
                    title: Text(s.logout),
                    textColor: Theme.of(context).colorScheme.error,
                    onTap: _busy ? null : _logout,
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _busy ? null : () => _run(_load),
                  child: Text(s.reload),
                ),
                const SizedBox(height: 24),
                ExistingEducationCoursesTile(
                    api: widget.api, auth: widget.auth),
                ConsentPanel(auth: widget.auth),
                const SizedBox(height: 24),
                SupportPanel(auth: widget.auth),
                if (widget.partnerEnabled) ...[
                  const SizedBox(height: 24),
                  PartnerPanel(
                    auth: widget.auth,
                    allowApply: widget.partnerApplyEnabled,
                  ),
                ],
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
                                RegExp(
                                  r'[\x00-\x1F\x7F-\x9F\u200B-\u200F\u202A-\u202E\u2060-\u206F\uFEFF]',
                                ).hasMatch(value)
                            ? s.invalid
                            : null,
                      ),
                      const SizedBox(height: 20),
                      Text(s.language),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: ['ru', 'kk', 'en']
                            .map(
                              (code) => ChoiceChip(
                                label: Text(
                                  {
                                    'ru': 'Русский',
                                    'kk': 'Қазақша',
                                    'en': 'English',
                                  }[code]!,
                                ),
                                selected: _language == code,
                                onSelected: _busy
                                    ? null
                                    : (_) => setState(() => _language = code),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 28),
                      FilledButton(
                        onPressed: _busy || _conflict ? null : _save,
                        child: Text(s.save),
                      ),
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
                          child: Text(s.reload),
                        ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                if (await _mayLeave() && mounted) {
                                  setState(() => _editing = false);
                                }
                              },
                        child: Text(s.cancel),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.auth.removeListener(_authChanged);
    _name.dispose();
    super.dispose();
  }
}
