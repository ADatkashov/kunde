import 'package:flutter/material.dart';

import 'core/localization/kunde_localizations.dart';
import 'features/executor/executor_screen.dart';
import 'features/home/data/kunde_api.dart';
import 'features/identity/auth_repository.dart';
import 'features/identity/auth_screen.dart';
import 'features/identity/phone_auth_gateway.dart';
import 'shared/theme/kunde_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  const endpoint = String.fromEnvironment('API_BASE_URL');
  final base = Uri.tryParse(endpoint);
  if (base == null || base.scheme != 'https' || !base.hasAuthority) {
    runApp(const MaterialApp(
      home: Scaffold(body: Center(child: Text('Executor API is unavailable'))),
    ));
    return;
  }
  final auth = AuthRepository(
    gateway: PhoneAuthGateway(apiBase: base),
    vault: SecureTokenVault(),
    apiBase: base,
  );
  runApp(ExecutorApp(auth: auth, api: KundeApi(baseUri: base)));
}

class ExecutorApp extends StatefulWidget {
  const ExecutorApp({required this.auth, required this.api, super.key});

  final AuthRepository auth;
  final KundeApi api;

  @override
  State<ExecutorApp> createState() => _ExecutorAppState();
}

class _ExecutorAppState extends State<ExecutorApp> {
  Locale? _locale;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'KUNDE Executor',
        debugShowCheckedModeBanner: false,
        theme: KundeTheme.light,
        darkTheme: KundeTheme.dark,
        locale: _locale,
        supportedLocales: KundeLocalizations.supportedLocales,
        localizationsDelegates: KundeLocalizations.localizationsDelegates,
        home: AuthScreen(
          auth: widget.auth,
          api: widget.api,
          partnerApplyEnabled: false,
          onLocale: (locale) => setState(() => _locale = locale),
          authorizedHome: (_) => ExecutorScreen(auth: widget.auth),
        ),
      );
}
