import 'package:flutter/material.dart';

import 'core/localization/kunde_localizations.dart';
import 'features/home/data/kunde_api.dart';
import 'features/shell/kunde_shell.dart';
import 'features/identity_poc/identity_poc_screen.dart';
import 'features/identity/auth_repository.dart';
import 'features/identity/auth_screen.dart';
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
  runApp(KundeApp(
    api: KundeApi(
      baseUri: Uri.parse(apiBaseUrl),
      timeout: const Duration(seconds: apiTimeoutSeconds),
    ),
    auth: const bool.fromEnvironment('CONSUMER_IDENTITY_ENABLED')
        ? AuthRepository(
            gateway: AppAuthGateway(
              issuer: const String.fromEnvironment('OIDC_ISSUER_URI'),
              clientId: const String.fromEnvironment('OIDC_CLIENT_ID',
                  defaultValue: 'kunde-consumer'),
            ),
            vault: SecureTokenVault(),
            apiBase: Uri.parse(apiBaseUrl),
          )
        : null,
    identityPocEnabled: const bool.fromEnvironment('IDENTITY_POC_ENABLED'),
  ));
}

class KundeApp extends StatefulWidget {
  const KundeApp(
      {required this.api,
      this.auth,
      this.identityPocEnabled = false,
      super.key});

  final KundeApi api;
  final AuthRepository? auth;
  final bool identityPocEnabled;

  @override
  State<KundeApp> createState() => _KundeAppState();
}

class _KundeAppState extends State<KundeApp> {
  Locale? _locale;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'KUNDE',
        debugShowCheckedModeBanner: false,
        theme: KundeTheme.light,
        darkTheme: KundeTheme.dark,
        localizationsDelegates: KundeLocalizations.localizationsDelegates,
        supportedLocales: KundeLocalizations.supportedLocales,
        locale: _locale,
        home: widget.auth != null
            ? AuthScreen(
                auth: widget.auth!,
                api: widget.api,
                onLocale: (locale) => setState(() => _locale = locale))
            : widget.identityPocEnabled
                ? const IdentityPocScreen()
                : KundeShell(api: widget.api),
      );
}
