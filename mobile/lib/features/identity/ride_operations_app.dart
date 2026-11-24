import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/localization/kunde_localizations.dart';
import 'auth_repository.dart';
import 'operator_gate.dart';
import 'phone_auth_gateway.dart';
import '../../shared/theme/kunde_theme.dart';

void runRideOperations(String title, Widget Function(AuthRepository) home,
    {bool sameOriginWeb = false}) {
  WidgetsFlutterBinding.ensureInitialized();
  const endpoint = String.fromEnvironment('API_BASE_URL');
  final base = kIsWeb && sameOriginWeb && endpoint.isEmpty
      ? Uri.base.resolve('/api/v1/')
      : Uri.tryParse(endpoint);
  final debugLoopback =
      kDebugMode && base?.scheme == 'http' && base?.host == 'localhost';
  if (base == null ||
      !base.hasAuthority ||
      (base.scheme != 'https' && !debugLoopback)) {
    runApp(MaterialApp(
      title: title,
      home:
          const Scaffold(body: Center(child: Text('Rides API is unavailable'))),
    ));
    return;
  }
  final auth = AuthRepository(
    gateway: PhoneAuthGateway(apiBase: base),
    vault:
        kIsWeb && sameOriginWeb ? _BrowserSessionVault() : SecureTokenVault(),
    apiBase: base,
  );
  runApp(RideOperationsApp(auth: auth, title: title, home: home));
}

class _BrowserSessionVault implements TokenVault {
  String? _session;

  @override
  Future<String?> read() async => _session;

  @override
  Future<void> write(String value) async {
    _session = value;
  }

  @override
  Future<void> clear() async {
    _session = null;
  }
}

class RideOperationsApp extends StatefulWidget {
  const RideOperationsApp(
      {required this.auth, required this.title, required this.home, super.key});

  final AuthRepository auth;
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
        home: OperatorGate(
          auth: widget.auth,
          onLocale: (locale) => setState(() => _locale = locale),
          authorizedHome: (_) => widget.home(widget.auth),
        ),
      );
}
