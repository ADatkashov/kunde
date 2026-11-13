import 'package:flutter/material.dart';

import '../../core/localization/kunde_localizations.dart';
import '../home/data/kunde_api.dart';
import '../home/presentation/home_screen.dart';
import '../home/presentation/super_app_widgets.dart';
import 'shell_strings.dart';
import 'tabs.dart';

/// Four-tab shell used when sign-in is not configured. With sign-in the same
/// bar and tabs are composed by `AuthScreen`, which owns the profile tab.
class KundeShell extends StatefulWidget {
  const KundeShell({required this.api, super.key});

  final KundeApi api;

  @override
  State<KundeShell> createState() => _KundeShellState();
}

class _KundeShellState extends State<KundeShell> {
  KundeTab _tab = KundeTab.home;

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    return Scaffold(
      body: switch (_tab) {
        KundeTab.home => HomeScreen(
            api: widget.api,
            onOpenSearch: () => setState(() => _tab = KundeTab.search),
            onOpenOrders: () => setState(() => _tab = KundeTab.orders)),
        KundeTab.search => SafeArea(child: SearchTab(api: widget.api)),
        KundeTab.orders => const SafeArea(child: OrdersTab()),
        KundeTab.profile => SafeArea(
            child: ListView(padding: const EdgeInsets.all(16), children: [
              EmptyStateCard(
                  icon: Icons.lock_outline,
                  title: s.profileNotConfiguredTitle,
                  body: s.profileNotConfiguredBody),
            ]),
          ),
      },
      bottomNavigationBar: KundeNavigationBar(
          selected: _tab, onSelected: (tab) => setState(() => _tab = tab)),
    );
  }
}
