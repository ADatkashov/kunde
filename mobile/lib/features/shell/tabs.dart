import 'package:flutter/material.dart';

import '../../core/localization/kunde_localizations.dart';
import '../home/data/kunde_api.dart';
import '../home/data/platform_snapshot.dart';
import '../home/presentation/catalog_search_panel.dart';
import '../home/presentation/super_app_widgets.dart';
import 'shell_strings.dart';

enum KundeTab { home, search, orders, profile }

class KundeNavigationBar extends StatelessWidget {
  const KundeNavigationBar(
      {required this.selected, required this.onSelected, super.key});

  final KundeTab selected;

  /// Null disables the bar (for example while a request is in flight).
  final ValueChanged<KundeTab>? onSelected;

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    return Semantics(
      container: true,
      label: s.navLabel,
      child: NavigationBar(
        selectedIndex: selected.index,
        onDestinationSelected:
            onSelected == null ? null : (i) => onSelected!(KundeTab.values[i]),
        destinations: [
          NavigationDestination(
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(Icons.home_rounded),
              label: s.navHome),
          NavigationDestination(
              icon: const Icon(Icons.search_rounded), label: s.navSearch),
          NavigationDestination(
              icon: const Icon(Icons.receipt_long_outlined),
              selectedIcon: const Icon(Icons.receipt_long_rounded),
              label: s.navOrders),
          NavigationDestination(
              icon: const Icon(Icons.person_outline),
              selectedIcon: const Icon(Icons.person_rounded),
              label: s.navProfile),
        ],
      ),
    );
  }
}

/// Search tab: real catalog search when the server enables the marketplace,
/// otherwise an honest empty state.
class SearchTab extends StatefulWidget {
  const SearchTab({required this.api, super.key});

  final KundeApi api;

  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  late Future<PlatformSnapshot> _snapshot;

  @override
  void initState() {
    super.initState();
    _snapshot = widget.api.loadPlatformSnapshot();
  }

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    return FutureBuilder<PlatformSnapshot>(
      future: _snapshot,
      builder: (context, state) {
        final done = state.connectionState == ConnectionState.done;
        final enabled = done && (state.data?.marketplaceEnabled ?? false);
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (!done)
                  const Center(
                      child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator()))
                else if (enabled)
                  CatalogSearchPanel(api: widget.api)
                else if (state.hasError)
                  EmptyStateCard(
                      icon: Icons.cloud_off_outlined,
                      title: s.offline,
                      body: s.retryHint)
                else
                  EmptyStateCard(
                      icon: Icons.search_off_rounded,
                      title: s.searchTabUnavailableTitle,
                      body: s.searchTabUnavailableBody),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Orders tab: there is no order capability yet, so it only explains that.
class OrdersTab extends StatelessWidget {
  const OrdersTab({super.key});

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            EmptyStateCard(
                icon: Icons.receipt_long_outlined,
                title: s.ordersEmptyTitle,
                body: s.ordersEmptyBody),
          ],
        ),
      ),
    );
  }
}
