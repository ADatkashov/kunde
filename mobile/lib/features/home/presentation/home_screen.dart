import 'package:flutter/material.dart';

import '../../../core/localization/kunde_localizations.dart';
import '../data/kunde_api.dart';
import '../data/platform_snapshot.dart';
import 'catalog_search_panel.dart';
import 'home_strings.dart';
import 'super_app_widgets.dart';

/// KUNDE Super App home. Only Food Ordering (Almaty) is an approved first
/// category; every other category is shown as "soon" and cannot start an
/// order. Live data comes only from the API; no demo restaurants or prices.
class HomeScreen extends StatefulWidget {
  const HomeScreen({required this.api, super.key});

  final KundeApi api;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<PlatformSnapshot> _snapshot;

  @override
  void initState() {
    super.initState();
    _snapshot = widget.api.loadPlatformSnapshot();
  }

  void _retry() {
    setState(() => _snapshot = widget.api.loadPlatformSnapshot());
  }

  void _showInfo(String title, String body) {
    final s = KundeLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(body),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(s.close)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openSearch() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(KundeLocalizations.of(context).searchLabel)),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [CatalogSearchPanel(api: widget.api)],
          ),
        ),
      ),
    ));
  }

  List<ServiceCategory> _categories(KundeLocalizations s, bool foodEnabled) => [
        ServiceCategory(
            icon: Icons.ramen_dining_rounded,
            label: s.catFood,
            color: const Color(0xFFC66A22),
            enabled: foodEnabled),
        ServiceCategory(
            icon: Icons.shopping_basket_rounded,
            label: s.catGroceries,
            color: const Color(0xFF2E8174)),
        ServiceCategory(
            icon: Icons.local_taxi_rounded,
            label: s.catRides,
            color: const Color(0xFFB7791F)),
        ServiceCategory(
            icon: Icons.inventory_2_rounded,
            label: s.catDelivery,
            color: const Color(0xFFA0522D)),
        ServiceCategory(
            icon: Icons.home_rounded,
            label: s.catHome,
            color: const Color(0xFF176B52)),
        ServiceCategory(
            icon: Icons.spa_rounded,
            label: s.catBeauty,
            color: const Color(0xFFB83280)),
        ServiceCategory(
            icon: Icons.favorite_rounded,
            label: s.catHealth,
            color: const Color(0xFFB9382D)),
        ServiceCategory(
            icon: Icons.directions_car_rounded,
            label: s.catAuto,
            color: const Color(0xFF1769AA)),
        ServiceCategory(
            icon: Icons.confirmation_number_rounded,
            label: s.catLeisure,
            color: const Color(0xFF8A5700)),
        ServiceCategory(
            icon: Icons.apps_rounded,
            label: s.catAll,
            color: const Color(0xFF0B6B5E),
            isAll: true),
      ];

  void _onCategory(
      ServiceCategory c, List<ServiceCategory> all, bool foodEnabled) {
    final s = KundeLocalizations.of(context);
    if (c.isAll) {
      _showAll(all);
    } else if (c.label == s.catFood) {
      foodEnabled ? _openSearch() : _showInfo(s.catFood, s.foodPreparingBody);
    } else {
      _showInfo(s.comingSoonTitle, s.comingSoonBody);
    }
  }

  void _showAll(List<ServiceCategory> all) {
    final s = KundeLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          children: [
            Text(s.allServicesTitle,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            for (final c in all.where((c) => !c.isAll))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(c.icon, color: c.color),
                title: Text(c.label),
                trailing:
                    c.enabled ? Text(s.categoryAvailable) : const SoonBadge(),
              ),
            const SizedBox(height: 8),
            Text(s.comingSoonBody),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: FutureBuilder<PlatformSnapshot>(
              future: _snapshot,
              builder: (context, state) {
                final loading = state.connectionState != ConnectionState.done;
                final failed = !loading && (state.hasError || !state.hasData);
                final snapshot = state.data;
                final marketplace = snapshot?.marketplaceEnabled ?? false;
                final categories = _categories(s, marketplace);
                void openSoon(String title, [String? body]) =>
                    _showInfo(title, body ?? s.comingSoonBody);
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    const HomeHeader(),
                    const SizedBox(height: 16),
                    HomeSearchField(
                        onTap: marketplace
                            ? _openSearch
                            : () => openSoon(
                                s.homeSearchHint, s.searchUnavailable)),
                    const SizedBox(height: 16),
                    FadeIn(child: const AiEntryCard()),
                    const SizedBox(height: 16),
                    if (failed) ...[
                      _OfflineCard(
                        title: s.offline,
                        hint: s.retryHint,
                        retryLabel: s.retry,
                        onRetry: _retry,
                      ),
                      const SizedBox(height: 16),
                    ],
                    FadeIn(
                      delay: 60,
                      child: CategoryGrid(
                        categories: categories,
                        onTap: (c) => _onCategory(c, categories, marketplace),
                      ),
                    ),
                    const SizedBox(height: 20),
                    FadeIn(
                      delay: 120,
                      child:
                          FoodBanner(onOrder: marketplace ? _openSearch : null),
                    ),
                    const SizedBox(height: 16),
                    LayoutBuilder(builder: (context, box) {
                      final actions = [
                        (Icons.inventory_2_outlined, s.quickOrders),
                        (Icons.favorite_border_rounded, s.quickFavorites),
                        (Icons.percent_rounded, s.quickPromo),
                        (Icons.account_balance_wallet_outlined, s.quickPay),
                      ];
                      final columns = box.maxWidth >= 560 ? 4 : 2;
                      final width =
                          (box.maxWidth - 8 * (columns - 1)) / columns;
                      return Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final a in actions)
                          SizedBox(
                              width: width,
                              child: QuickAction(
                                  icon: a.$1,
                                  label: a.$2,
                                  onTap: () => openSoon(
                                      s.comingSoonTitle, s.comingSoonBody))),
                      ]);
                    }),
                    const SizedBox(height: 24),
                    SectionTitle(title: s.nearbyTitle, trailing: s.homeCity),
                    const SizedBox(height: 12),
                    EmptyStateCard(
                        icon: Icons.storefront_outlined,
                        title: s.nearbyEmptyTitle,
                        body: s.nearbyEmptyBody),
                    const SizedBox(height: 24),
                    _PlatformStatus(
                        loading: loading, snapshot: snapshot, strings: s),
                    const SizedBox(height: 16),
                    Text('KUNDE',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelMedium?.copyWith(
                            letterSpacing: 2,
                            color: theme.colorScheme.onSurfaceVariant)),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PlatformStatus extends StatelessWidget {
  const _PlatformStatus(
      {required this.loading, required this.snapshot, required this.strings});

  final bool loading;
  final PlatformSnapshot? snapshot;
  final KundeLocalizations strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snap = snapshot;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(strings.connectionLabel, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (loading)
              const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2))
            else if (snap == null)
              Text(strings.offline)
            else ...[
              Text(snap.marketplaceEnabled
                  ? strings.marketplaceReadyTitle
                  : strings.servicesUnavailableTitle),
              Text(strings.connected),
              const SizedBox(height: 4),
              _CapabilityLine(
                icon: Icons.storefront_outlined,
                label: strings.marketplaceLabel,
                enabled: snap.marketplaceEnabled,
              ),
              _CapabilityLine(
                icon: Icons.auto_awesome_outlined,
                label:
                    snap.aiEnabled ? strings.aiEnabled : strings.aiUnavailable,
                enabled: snap.aiEnabled,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OfflineCard extends StatelessWidget {
  const _OfflineCard(
      {required this.title,
      required this.hint,
      required this.retryLabel,
      required this.onRetry});

  final String title;
  final String hint;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(hint),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(retryLabel),
              ),
            ],
          ),
        ),
      );
}

class _CapabilityLine extends StatelessWidget {
  const _CapabilityLine(
      {required this.icon, required this.label, required this.enabled});

  final IconData icon;
  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Semantics(
        label: '$label: ${enabled ? s.available : s.notAvailable}',
        child: ExcludeSemantics(
          child: Row(
            children: [
              Icon(enabled ? Icons.check_circle : icon,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(label,
                      style: Theme.of(context).textTheme.bodyMedium)),
              Text(enabled ? s.available : s.notAvailable),
            ],
          ),
        ),
      ),
    );
  }
}
