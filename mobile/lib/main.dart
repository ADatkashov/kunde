import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'core/localization/kunde_localizations.dart';
import 'features/booking/booking_services.dart';
import 'features/booking/data/booking_api.dart';
import 'features/food/data/cart_controller.dart';
import 'features/food/data/food_api.dart';
import 'features/food/food_services.dart';
import 'features/home/data/kunde_api.dart';
import 'features/shell/kunde_shell.dart';
import 'features/identity_poc/identity_poc_screen.dart';
import 'features/identity/auth_repository.dart';
import 'features/identity/auth_screen.dart';
import 'features/identity/phone_auth_gateway.dart';
import 'shared/theme/kunde_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080/api/v1/',
  );
  // Render Free sleeps when idle; a cold start takes about a minute.
  const apiTimeoutSeconds = int.fromEnvironment(
    'API_TIMEOUT_SECONDS',
    defaultValue: 4,
  );
  final auth = const bool.fromEnvironment('PHONE_AUTH_ENABLED')
      ? AuthRepository(
          gateway: PhoneAuthGateway(apiBase: Uri.parse(apiBaseUrl)),
          vault: SecureTokenVault(),
          apiBase: Uri.parse(apiBaseUrl),
        )
      : const bool.fromEnvironment('CONSUMER_IDENTITY_ENABLED')
          ? AuthRepository(
              gateway: AppAuthGateway(
                issuer: const String.fromEnvironment('OIDC_ISSUER_URI'),
                clientId: const String.fromEnvironment('OIDC_CLIENT_ID',
                    defaultValue: 'kunde-consumer'),
              ),
              vault: SecureTokenVault(),
              apiBase: Uri.parse(apiBaseUrl),
            )
          : null;
  runApp(KundeApp(
    api: KundeApi(
      baseUri: Uri.parse(apiBaseUrl),
      timeout: const Duration(seconds: apiTimeoutSeconds),
    ),
    auth: auth,
    // Food screens only appear when the server reports marketplaceEnabled (DEV pilot); never in production.
    food: auth == null
        ? null
        : FoodServices(
            api: FoodApi(
                baseUri: Uri.parse(apiBaseUrl),
                auth: auth,
                timeout: const Duration(
                    seconds: apiTimeoutSeconds < 20 ? 20 : apiTimeoutSeconds)),
            cart: CartController(),
            auth: auth),
    booking: auth == null
        ? null
        : BookingServices(
            api: BookingApi(
                baseUri: Uri.parse(apiBaseUrl),
                auth: auth,
                timeout: const Duration(
                    seconds: apiTimeoutSeconds < 20 ? 20 : apiTimeoutSeconds)),
            auth: auth),
    identityPocEnabled: const bool.fromEnvironment('IDENTITY_POC_ENABLED'),
    devOtpHint: const bool.fromEnvironment('DEV_OTP_HINT'),
    partnerEnabled: const bool.fromEnvironment('PARTNER_FEATURES_ENABLED'),
    partnerApplyEnabled: const bool.fromEnvironment('PARTNER_APPLY_ENABLED'),
  ));
}

class KundeApp extends StatefulWidget {
  const KundeApp(
      {required this.api,
      this.auth,
      this.identityPocEnabled = false,
      this.devOtpHint = false,
      this.partnerEnabled = false,
      this.partnerApplyEnabled = true,
      this.food,
      this.booking,
      super.key});

  final KundeApi api;
  final AuthRepository? auth;
  final bool identityPocEnabled;

  /// DEV builds only: show the fixed test code on the OTP screen.
  final bool devOtpHint;

  /// Partner screens (ADR-018); off by default and in every consumer build.
  final bool partnerEnabled;

  /// Show «Become a partner» to users who are not partner staff (PARTNER_APPLY_ENABLED; off in production main).
  final bool partnerApplyEnabled;
  final FoodServices? food;
  final BookingServices? booking;

  @override
  State<KundeApp> createState() => _KundeAppState();
}

class _KundeAppState extends State<KundeApp> {
  static const _storage = FlutterSecureStorage();
  static const _themeKey = 'kunde.consumer.theme.v1';
  Locale? _locale;
  ThemeMode _theme = ThemeMode.light;
  bool _themeChanged = false;

  @override
  void initState() {
    super.initState();
    _restoreTheme();
  }

  Future<void> _restoreTheme() async {
    try {
      final saved = await _storage.read(key: _themeKey);
      if (mounted && !_themeChanged && saved == 'dark') {
        setState(() => _theme = ThemeMode.dark);
      }
    } on Exception {
      // Keep the default when device preferences cannot be read.
    }
  }

  Future<void> _setTheme(ThemeMode mode) async {
    setState(() {
      _themeChanged = true;
      _theme = mode;
    });
    try {
      await _storage.write(key: _themeKey, value: mode.name);
    } on Exception {
      // The selection still applies for this session.
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'KUNDE',
        debugShowCheckedModeBanner: false,
        theme: KundeTheme.light,
        darkTheme: KundeTheme.dark,
        themeMode: _theme,
        localizationsDelegates: KundeLocalizations.localizationsDelegates,
        supportedLocales: KundeLocalizations.supportedLocales,
        locale: _locale,
        home: widget.auth != null
            ? AuthScreen(
                auth: widget.auth!,
                api: widget.api,
                devOtpHint: widget.devOtpHint,
                partnerEnabled: widget.partnerEnabled,
                partnerApplyEnabled: widget.partnerApplyEnabled,
                food: widget.food,
                booking: widget.booking,
                onTheme: _setTheme,
                onLocale: (locale) => setState(() => _locale = locale))
            : widget.identityPocEnabled
                ? const IdentityPocScreen()
                : KundeShell(api: widget.api),
      );
}
