import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/strings.dart';
import '../core/theme.dart';
import '../features/login/login_screen.dart';
import '../features/login/partner_gate.dart';
import '../features/shell/partner_shell.dart';
import '../widgets/states.dart';
import 'app_controller.dart';
import 'settings.dart';

class KundePartnerApp extends StatelessWidget {
  const KundePartnerApp(
      {required this.controller, required this.settings, super.key});
  final AppController controller;
  final SettingsController settings;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: settings,
        builder: (context, _) => MaterialApp(
          title: 'KUNDE Partner',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: settings.themeMode,
          locale: settings.locale,
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: S.supported,
          // Unsupported phone languages fall back to Russian.
          localeResolutionCallback: (locale, supported) {
            for (final l in supported) {
              if (l.languageCode == locale?.languageCode) return l;
            }
            return const Locale('ru');
          },
          home: RootGate(controller: controller, settings: settings),
        ),
      );
}

/// Chooses the screen from the authentication/partner phase.
class RootGate extends StatelessWidget {
  const RootGate({required this.controller, required this.settings, super.key});
  final AppController controller;
  final SettingsController settings;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          switch (controller.phase) {
            case AppPhase.booting:
              return const Scaffold(body: SkeletonList(count: 3));
            case AppPhase.signedOut:
              return LoginScreen(controller: controller);
            case AppPhase.unreachable:
              return UnreachableScreen(controller: controller);
            case AppPhase.choosingPartner:
              return ChoosePartnerScreen(controller: controller);
            case AppPhase.noAccess:
              return NoAccessScreen(controller: controller);
            case AppPhase.ready:
              // Keyed by partner so switching business rebuilds all state.
              return PartnerShell(
                key: ValueKey(controller.partner?.id),
                controller: controller,
                settings: settings,
              );
          }
        },
      );
}
