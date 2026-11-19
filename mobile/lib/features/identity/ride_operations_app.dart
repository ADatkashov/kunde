import 'package:flutter/material.dart';

import '../../core/localization/kunde_localizations.dart';
import '../home/data/kunde_api.dart';
import 'auth_repository.dart';
import 'auth_screen.dart';
import 'phone_auth_gateway.dart';
import '../../shared/theme/kunde_theme.dart';

void runRideOperations(String title, Widget Function(AuthRepository) home) {
  WidgetsFlutterBinding.ensureInitialized();
  const endpoint = String.fromEnvironment('API_BASE_URL');
  final base = Uri.tryParse(endpoint);
  if (base == null || base.scheme != 'https' || !base.hasAuthority) {
    runApp(MaterialApp(
      title: title,
      home:
          const Scaffold(body: Center(child: Text('Rides API is unavailable'))),
    ));
    return;
  }
  final auth = AuthRepository(
    gateway: PhoneAuthGateway(apiBase: base),
    vault: SecureTokenVault(),
    apiBase: base,
  );
  runApp(RideOperationsApp(
      auth: auth, api: KundeApi(baseUri: base), title: title, home: home));
}

class RideOperationsApp extends StatefulWidget {
  const RideOperationsApp(
      {required this.auth,
      required this.api,
      required this.title,
      required this.home,
      super.key});

  final AuthRepository auth;
  final KundeApi api;
  final String title;
  final Widget Function(AuthRepository) home;

  @override
  State<RideOperationsApp> createState() => _RideOperationsAppState();
}

class _RideOperationsAppState extends State<RideOperationsApp> {
  Locale? _locale;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: widget.title,
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
          authorizedHome: (_) => widget.home(widget.auth),
        ),
      );
}
