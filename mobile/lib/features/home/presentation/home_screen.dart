import 'dart:async';

import '../../assistant/assistant_screen.dart';
import '../../auto/auto_services.dart';
import '../../auto/presentation/auto_home_screen.dart';
import '../../booking/booking_services.dart';
import '../../booking/presentation/category_screens.dart';
import '../../delivery/delivery_api.dart';
import '../../delivery/delivery_screen.dart';
import '../../food/food_services.dart';
import '../../food/presentation/food_home_screen.dart';
import '../../health/health_home_screen.dart';
import '../../rides/ride_api.dart';
import '../../rides/rides_screen.dart';

import 'package:flutter/material.dart';

import '../../../core/localization/kunde_localizations.dart';
import '../data/kunde_api.dart';
import '../data/platform_snapshot.dart';
import 'catalog_search_panel.dart';
import 'home_strings.dart';
import 'super_app_widgets.dart';

/// KUNDE home. The platform snapshot controls the available catalog routes.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.api,
    this.onOpenSearch,
    this.onOpenOrders,
    this.onOpenAssistant,
    this.food,
    this.booking,
    this.auto,
    this.rides,
    this.delivery,
    super.key,
  });

  final KundeApi api;

  /// When the host has a Search tab it switches to it; otherwise search opens
  /// as a pushed page.
  final VoidCallback? onOpenSearch;

  /// KUNDE Food screens; when set and the server enables the marketplace, Food opens the restaurant catalog.
  final FoodServices? food;

  /// Service booking (barbershops); shown when the server enables it.
  final BookingServices? booking;

  /// KUNDE Auto; shown when the server enables it.
  final AutoServices? auto;
  final RideApi? rides;
  final DeliveryApi? delivery;

  /// Opens the Orders tab when the host has one.
  final VoidCallback? onOpenOrders;
  final VoidCallback? onOpenAssistant;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<PlatformSnapshot> _snapshot;
  bool _deliveryResume = false;

  @override
  void initState() {
    super.initState();
    _snapshot = _loadSnapshot();
  }

  void _retry() {
    setState(() {
      _deliveryResume = false;
      _snapshot = _loadSnapshot();
    });
  }

  Future<PlatformSnapshot> _loadSnapshot() async {
    final snapshot = await widget.api.loadPlatformSnapshot();
    final api = widget.delivery;
    if (!snapshot.deliveryEnabled && api != null) {
      unawaited(_checkActiveDeliveries(api));
    }
    return snapshot;
  }

  Future<void> _checkActiveDeliveries(DeliveryApi api) async {
    try {
      final active = (await api.history()).any((order) => order.active);
      if (mounted && active) setState(() => _deliveryResume = true);
    } catch (_) {
      // Capability discovery stays available while the account history is offline.
    }
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
                  child: Text(s.close),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openFood() => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => FoodHomeScreen(services: widget.food!),
        ),
      );

  Future<void> _openDelivery() async {
    final snapshot = await _snapshot;
    if (!mounted || (!snapshot.deliveryEnabled && !_deliveryResume)) return;
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => DeliveryScreen(
        api: widget.delivery!,
        synthetic: snapshot.deliverySyntheticRouting,
        intakeEnabled: snapshot.deliveryEnabled,
      ),
    ));
  }

  void _openSearch() {
    if (widget.onOpenSearch != null) {
      widget.onOpenSearch!();
      return;
    }
    if (widget.food != null) {
      _openFood();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: Text(KundeLocalizations.of(context).searchLabel),
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [CatalogSearchPanel(api: widget.api)],
            ),
          ),
        ),
      ),
    );
  }

  List<ServiceCategory> _categories(
    KundeLocalizations s,
    bool foodEnabled,
    bool bookingEnabled,
    bool ridesEnabled,
    bool deliveryEnabled, {
    bool autoEnabled = false,
    bool healthEnabled = false,
  }) =>
      [
        ServiceCategory(
          icon: Icons.ramen_dining_rounded,
          label: s.catFood,
          color: const Color(0xFFC66A22),
          enabled: foodEnabled,
        ),
        ServiceCategory(
          icon: Icons.shopping_basket_rounded,
          label: s.catGroceries,
          color: const Color(0xFF2E8174),
          enabled: foodEnabled && widget.food != null,
        ),
        ServiceCategory(
          icon: Icons.local_florist_rounded,
          label: s.catFlowers,
          color: const Color(0xFFB83280),
          enabled: foodEnabled && widget.food != null,
        ),
        ServiceCategory(
          icon: Icons.local_taxi_rounded,
          label: s.catRides,
          color: const Color(0xFFB7791F),
          enabled: ridesEnabled && widget.rides != null,
        ),
        ServiceCategory(
          icon: Icons.inventory_2_rounded,
          label: s.catDelivery,
          color: const Color(0xFFA0522D),
          enabled: deliveryEnabled && widget.delivery != null,
        ),
        ServiceCategory(
          icon: Icons.home_rounded,
          label: s.catHome,
          color: const Color(0xFF176B52),
          enabled: bookingEnabled && widget.booking != null,
        ),
        ServiceCategory(
          icon: Icons.content_cut_rounded,
          label: s.catBeauty,
          color: const Color(0xFFB83280),
          enabled: bookingEnabled && widget.booking != null,
        ),
        ServiceCategory(
          icon: Icons.favorite_rounded,
          label: s.catHealth,
          enabled: healthEnabled && widget.booking != null,
          color: const Color(0xFFB9382D),
        ),
        ServiceCategory(
          icon: Icons.directions_car_rounded,
          label: s.catAuto,
          color: const Color(0xFF1769AA),
          enabled: autoEnabled && widget.auto != null,
        ),
        ServiceCategory(
          icon: Icons.confirmation_number_rounded,
          label: s.catLeisure,
          color: const Color(0xFF8A5700),
        ),
        ServiceCategory(
          icon: Icons.apps_rounded,
          label: s.catAll,
          color: const Color(0xFF0B6B5E),
          isAll: true,
        ),
      ];

  void _onCategory(
    ServiceCategory c,
    List<ServiceCategory> all,
    bool foodEnabled,
    bool bookingEnabled,
  ) {
    final s = KundeLocalizations.of(context);
    if (c.isAll) {
      _showAll(all, foodEnabled, bookingEnabled);
    } else if (c.label == s.catRides && c.enabled && widget.rides != null) {
      Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => RidesScreen(api: widget.rides!)),
      );
    } else if (c.label == s.catDelivery &&
        c.enabled &&
        widget.delivery != null) {
      unawaited(_openDelivery());
    } else if (c.label == s.catBeauty &&
        bookingEnabled &&
        widget.booking != null) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => BeautyCategoryScreen(services: widget.booking!),
        ),
      );
    } else if (c.label == s.catHome &&
        bookingEnabled &&
        widget.booking != null) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => HomeServicesCategoryScreen(services: widget.booking!),
        ),
      );
    } else if (c.label == s.catHealth && c.enabled && widget.booking != null) {
      Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => HealthHomeScreen(services: widget.booking!),
      ));
    } else if (c.label == s.catAuto && c.enabled && widget.auto != null) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AutoHomeScreen(services: widget.auto!),
        ),
      );
    } else if (c.label == s.catGroceries &&
        foodEnabled &&
        widget.food != null) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              FoodHomeScreen(services: widget.food!, vertical: 'GROCERY'),
        ),
      );
    } else if (c.label == s.catFlowers && foodEnabled && widget.food != null) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              FoodHomeScreen(services: widget.food!, vertical: 'FLOWERS_GIFTS'),
        ),
      );
    } else if (c.label == s.catFood) {
      if (foodEnabled) {
        if (widget.food == null) {
          _openSearch();
        } else {
          _openFood();
        }
      } else {
        _showInfo(s.catFood, s.foodPreparingBody);
      }
    } else {
      _showInfo(s.comingSoonTitle, s.comingSoonBody);
    }
  }

  void _showAll(
    List<ServiceCategory> all,
    bool foodEnabled,
    bool bookingEnabled,
  ) {
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
            Text(
              s.allServicesTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            for (final c in all.where((c) => !c.isAll))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(c.icon, color: c.color),
                title: Text(c.label),
                onTap: () {
                  Navigator.of(context).pop();
                  _onCategory(c, all, foodEnabled, bookingEnabled);
                },
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
                final snapshot = loading ? null : state.data;
                final marketplace = snapshot?.marketplaceEnabled ?? false;
                final categories = _categories(
                  s,
                  marketplace,
                  snapshot?.bookingEnabled ?? false,
                  snapshot?.ridesEnabled ?? false,
                  (snapshot?.deliveryEnabled ?? false) || _deliveryResume,
                  autoEnabled: snapshot?.autoEnabled ?? false,
                  healthEnabled: snapshot?.healthEnabled ?? false,
                );
                final visibleCategories = [
                  for (final label in [
                    s.catFood,
                    s.catGroceries,
                    if (snapshot?.ridesEnabled == true && widget.rides != null)
                      s.catRides,
                    if ((snapshot?.deliveryEnabled == true ||
                            _deliveryResume) &&
                        widget.delivery != null)
                      s.catDelivery,
                    s.catHome,
                    s.catBeauty,
                    s.catAuto,
                    s.catLeisure,
                    s.catHealth,
                    s.catAll,
                  ])
                    categories.firstWhere(
                      (category) => category.label == label,
                    ),
                ];
                void openAssistant() => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const AssistantScreen(),
                      ),
                    );
                void openSoon(String title, [String? body]) =>
                    _showInfo(title, body ?? s.comingSoonBody);
                final promos = [
                  HomePromoCard(
                    promotion: HomePromotion.assistant,
                    label: s.homeAiTitle,
                    onTap: widget.onOpenAssistant ?? openAssistant,
                  ),
                  HomePromoCard(
                    promotion: HomePromotion.rewards,
                    label: s.homeRewards,
                    onTap: () => openSoon(s.homeRewards),
                  ),
                  HomePromoCard(
                    promotion: HomePromotion.membership,
                    label: 'KUNDE+',
                    onTap: () => openSoon('KUNDE+'),
                  ),
                ];
                final stackedPromos =
                    MediaQuery.textScalerOf(context).scale(1) > 1.5;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  children: [
                    HomeHeader(
                      onNotifications: () => openSoon(
                        s.homeNotifications,
                        s.homeNotificationsUnavailable,
                      ),
                    ),
                    const SizedBox(height: 4),
                    HomeSearchField(
                      onTap: marketplace ||
                              (snapshot?.bookingEnabled == true &&
                                  widget.booking != null)
                          ? _openSearch
                          : () =>
                              openSoon(s.homeSearchHint, s.searchUnavailable),
                    ),
                    const SizedBox(height: 16),
                    FadeIn(
                      delay: 120,
                      child: FoodBanner(
                        onOrder: marketplace
                            ? (widget.food == null ? _openSearch : _openFood)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FadeIn(
                      child: stackedPromos
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              spacing: 8,
                              children: promos,
                            )
                          : IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                spacing: 8,
                                children: [
                                  for (final promo in promos)
                                    Expanded(child: promo),
                                ],
                              ),
                            ),
                    ),
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
                      child: loading
                          ? const _CategorySkeleton()
                          : CategoryGrid(
                              categories: visibleCategories,
                              onTap: (c) => _onCategory(
                                c,
                                categories,
                                marketplace,
                                snapshot?.bookingEnabled ?? false,
                              ),
                            ),
                    ),
                    const SizedBox(height: 6),
                    SectionTitle(
                      title: s.nearbyTitle,
                      action: marketplace
                          ? TextButton(
                              onPressed: _openSearch,
                              child: Text(s.nearbySeeAll,
                                  textAlign: TextAlign.end),
                            )
                          : null,
                    ),
                    if (loading)
                      const _CategorySkeleton()
                    else if (marketplace && widget.food != null) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: ServicePhotoCard(
                              label: s.nearbyRestaurants,
                              asset: 'assets/photos/nearby-restaurants.webp',
                              onTap: _openFood,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ServicePhotoCard(
                              label: s.nearbyStores,
                              asset: 'assets/photos/nearby-groceries.webp',
                              onTap: () => _onCategory(
                                categories.firstWhere(
                                  (c) => c.label == s.catGroceries,
                                ),
                                categories,
                                marketplace,
                                snapshot?.bookingEnabled ?? false,
                              ),
                            ),
                          ),
                          if (snapshot?.bookingEnabled == true &&
                              widget.booking != null) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: ServicePhotoCard(
                                label: s.catHome,
                                asset: 'assets/photos/nearby-home.webp',
                                onTap: () => _onCategory(
                                  categories.firstWhere(
                                    (c) => c.label == s.catHome,
                                  ),
                                  categories,
                                  marketplace,
                                  true,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      FoodNearbySection(services: widget.food!),
                    ] else if (!failed)
                      EmptyStateCard(
                        icon: Icons.storefront_outlined,
                        title: s.nearbyEmptyTitle,
                        body: s.nearbyEmptyBody,
                      ),
                    if (widget.onOpenOrders != null) ...[
                      const SizedBox(height: 16),
                      QuickAction(
                        icon: Icons.receipt_long_outlined,
                        label: s.quickOrders,
                        onTap: widget.onOpenOrders!,
                      ),
                    ],
                    if (snapshot?.bookingEnabled == true &&
                        widget.booking != null) ...[
                      const SizedBox(height: 24),
                      SectionTitle(title: s.catServices),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: ServicePhotoCard(
                              label: s.catHome,
                              asset: 'assets/photos/home-services.jpg',
                              onTap: () => _onCategory(
                                categories.firstWhere(
                                  (c) => c.label == s.catHome,
                                ),
                                categories,
                                marketplace,
                                true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ServicePhotoCard(
                              label: s.catBeauty,
                              asset: 'assets/photos/beauty.jpg',
                              onTap: () => _onCategory(
                                categories.firstWhere(
                                  (c) => c.label == s.catBeauty,
                                ),
                                categories,
                                marketplace,
                                true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 24),
                    _PlatformStatus(
                      loading: loading,
                      snapshot: snapshot,
                      strings: s,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'KUNDE',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelMedium?.copyWith(
                        letterSpacing: 2,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
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
  const _PlatformStatus({
    required this.loading,
    required this.snapshot,
    required this.strings,
  });

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
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (snap == null)
              Text(strings.offline)
            else ...[
              Text(
                snap.marketplaceEnabled
                    ? strings.marketplaceReadyTitle
                    : strings.servicesUnavailableTitle,
              ),
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
  const _OfflineCard({
    required this.title,
    required this.hint,
    required this.retryLabel,
    required this.onRetry,
  });

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
  const _CapabilityLine({
    required this.icon,
    required this.label,
    required this.enabled,
  });

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
              Icon(
                enabled ? Icons.check_circle : icon,
                size: 20,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              Text(enabled ? s.available : s.notAvailable),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategorySkeleton extends StatelessWidget {
  const _CategorySkeleton();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Row(
          children: [
            for (var i = 0; i < 3; i++)
              Expanded(
                child: Card(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const SizedBox(height: 92),
                ),
              ),
          ],
        ),
      );
}
