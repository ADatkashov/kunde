import 'package:flutter/material.dart';

import 'core/localization/kunde_localizations.dart';
import 'features/home/data/kunde_api.dart';
import 'features/home/presentation/home_screen.dart';
import 'features/identity_poc/identity_poc_screen.dart';
import 'shared/theme/kunde_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080/api/v1/',
  );
  runApp(KundeApp(
    api: KundeApi(baseUri: Uri.parse(apiBaseUrl)),
    identityPocEnabled: const bool.fromEnvironment('IDENTITY_POC_ENABLED'),
  ));
}

class KundeApp extends StatelessWidget {
  const KundeApp({required this.api, this.identityPocEnabled = false, super.key});

  final KundeApi api;
  final bool identityPocEnabled;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'KUNDE',
        debugShowCheckedModeBanner: false,
        theme: KundeTheme.light,
        darkTheme: KundeTheme.dark,
        localizationsDelegates: KundeLocalizations.localizationsDelegates,
        supportedLocales: KundeLocalizations.supportedLocales,
        home: identityPocEnabled
            ? const IdentityPocScreen()
            : HomeScreen(api: api),
      );
}
