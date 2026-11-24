import 'package:flutter/material.dart';

import 'package:kunde_localization/kunde_localizations.dart';
import '../food/food_services.dart';
import '../food/presentation/food_home_screen.dart';
import '../home/data/kunde_api.dart';
import '../home/presentation/home_strings.dart';
import '../home/data/platform_snapshot.dart';
import '../home/presentation/catalog_search_panel.dart';
import '../home/presentation/super_app_widgets.dart';
import 'shell_strings.dart';
import '../booking/booking_services.dart';
import '../leisure/data/leisure_api.dart';
import 'package:kunde_models/leisure_models.dart';
import '../leisure/leisure_services.dart';
import '../leisure/presentation/leisure_list_screen.dart';
import '../leisure/presentation/leisure_strings.dart';
import '../booking/presentation/services_home_screen.dart';

enum KundeTab { home, search, assistant, orders, profile }

class KundeNavigationBar extends StatelessWidget {
  const KundeNavigationBar({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final KundeTab selected;

  /// Null disables the bar (for example while a request is in flight).
  final ValueChanged<KundeTab>? onSelected;

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final labels = [s.navHome, s.navSearch, 'AI', s.navOrders, s.navProfile];
    final labelStyle = theme.textTheme.labelMedium!.copyWith(letterSpacing: 0);
    final textScaler =
        MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);
    final availableWidth = (MediaQuery.sizeOf(context).width -
                MediaQuery.paddingOf(context).horizontal) /
            labels.length -
        4;
    var fontSize = labelStyle.fontSize!;
    for (final label in labels) {
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: labelStyle.copyWith(fontSize: fontSize),
        ),
        textDirection: Directionality.of(context),
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      if (painter.width > availableWidth) {
        fontSize *= availableWidth / painter.width;
      }
      painter.dispose();
    }
    return Semantics(
      container: true,
      label: s.navLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.outlineVariant)),
          boxShadow: [
            BoxShadow(
              color: colors.shadow.withValues(alpha: .09),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: NavigationBar(
          height: 64,
          animationDuration: const Duration(milliseconds: 180),
          indicatorColor: colors.primaryContainer,
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => labelStyle.copyWith(
              fontSize: fontSize,
              color: states.contains(WidgetState.selected)
                  ? colors.onSurface
                  : colors.onSurfaceVariant,
            ),
          ),
          selectedIndex: selected.index,
          onDestinationSelected: onSelected == null
              ? null
              : (i) => onSelected!(KundeTab.values[i]),
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(Icons.home_rounded),
              label: s.navHome,
            ),
            NavigationDestination(
              icon: const Icon(Icons.search_rounded),
              label: s.navSearch,
            ),
            const NavigationDestination(icon: AiOrb(size: 40), label: 'AI'),
            NavigationDestination(
              icon: const Icon(Icons.shopping_bag_outlined),
              selectedIcon: const Icon(Icons.shopping_bag_rounded),
              label: s.navOrders,
            ),
            NavigationDestination(
              icon: const Icon(Icons.person_outline),
              selectedIcon: const Icon(Icons.person_rounded),
              label: s.navProfile,
            ),
          ],
        ),
      ),
    );
  }
}

/// Search tab: real catalog search when the server enables the marketplace,
/// otherwise an honest empty state.
class SearchTab extends StatefulWidget {
  const SearchTab(
      {required this.api, this.food, this.booking, this.leisure, super.key});

  final KundeApi api;
  final FoodServices? food;
  final BookingServices? booking;
  final LeisureServices? leisure;

  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  late Future<PlatformSnapshot> _snapshot;
  bool _openOnly = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _snapshot = widget.api.loadPlatformSnapshot();
  }

  /// Global search: the server says whether the words are a ticketed event (Events) or a bookable activity (Leisure).
  Future<void> _searchEverything(String query) async {
    final leisure = widget.leisure;
    if (leisure == null || query.trim().isEmpty) return;
    final s = KundeLocalizations.of(context);
    SearchRoute route;
    try {
      route = await leisure.api.route(query);
    } on LeisureException {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.offline)));
      }
      return;
    }
    if (!mounted) return;
    void open(LeisureProduct product) => Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => LeisureListScreen(
              services: leisure.forProduct(product),
              title: query.trim(),
              initial: LeisureFilter(
                  query: route.category == null ? query.trim() : '',
                  category: route.category),
            ),
          ),
        );
    switch (route.route) {
      case 'EVENTS':
        open(LeisureProduct.events);
      case 'LEISURE':
        open(LeisureProduct.leisure);
      case 'BOTH':
        await showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (sheet) => SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(title: Text(s.gsBoth)),
              ListTile(
                leading: const Icon(Icons.confirmation_number_rounded),
                title: Text(s.catEvents),
                onTap: () {
                  Navigator.pop(sheet);
                  open(LeisureProduct.events);
                },
              ),
              ListTile(
                leading: const Icon(Icons.sports_esports_rounded),
                title: Text(s.catLeisure),
                onTap: () {
                  Navigator.pop(sheet);
                  open(LeisureProduct.leisure);
                },
              ),
            ]),
          ),
        );
      default:
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.gsNone)));
    }
  }

  void _openFood(FoodServices food, String vertical) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FoodHomeScreen(services: food, vertical: vertical),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    return FutureBuilder<PlatformSnapshot>(
      future: _snapshot,
      builder: (context, state) {
        final done = state.connectionState == ConnectionState.done;
        final enabled = done && (state.data?.marketplaceEnabled ?? false);
        final canBrowseBookings = done &&
            state.data?.bookingEnabled == true &&
            widget.booking != null;
        final homeServicesEnabled = state.data?.homeServicesEnabled == true;
        final beautyEnabled = state.data?.beautyEnabled == true;
        final food = widget.food;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                HomeHeader(
                  onNotifications: () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(s.homeNotifications),
                      content: Text(s.homeNotificationsUnavailable),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            MaterialLocalizations.of(context).okButtonLabel,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Text(
                  s.catalogTitle,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                Text(s.catalogSubtitle),
                const SizedBox(height: 16),
                if (widget.leisure != null &&
                    done &&
                    (state.data?.eventsEnabled == true ||
                        state.data?.leisureEnabled == true)) ...[
                  TextField(
                    textInputAction: TextInputAction.search,
                    onSubmitted: _searchEverything,
                    decoration: InputDecoration(
                      hintText: s.gsHint,
                      prefixIcon:
                          const Icon(Icons.confirmation_number_outlined),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (!done)
                  Center(
                    child: const CircularProgressIndicator(),
                  )
                else if (enabled || canBrowseBookings) ...[
                  if (enabled)
                    CatalogSearchPanel(
                      api: widget.api,
                      label: s.catalogSearchHint,
                      onQueryChanged: food == null
                          ? null
                          : (value) => setState(() => _query = value),
                    ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (enabled && food != null)
                        for (final (icon, label, vertical) in [
                          (Icons.restaurant_outlined, s.catFood, 'FOOD'),
                          (
                            Icons.shopping_basket_outlined,
                            s.catGroceries,
                            'GROCERY',
                          ),
                          (
                            Icons.local_florist_outlined,
                            s.catFlowers,
                            'FLOWERS_GIFTS',
                          ),
                        ])
                          ActionChip(
                            avatar: Icon(icon, size: 18),
                            label: Text(label),
                            onPressed: () => _openFood(food, vertical),
                          ),
                      ActionChip(
                        avatar: const Icon(
                          Icons.home_repair_service_outlined,
                          size: 18,
                        ),
                        label: Text(
                          canBrowseBookings
                              ? s.catServices
                              : '${s.catServices} · ${s.homeSoon}',
                        ),
                        onPressed: canBrowseBookings
                            ? () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => ServicesHomeScreen(
                                      services: widget.booking!,
                                      homeServicesEnabled: homeServicesEnabled,
                                      beautyEnabled: beautyEnabled,
                                    ),
                                  ),
                                )
                            : null,
                      ),
                    ],
                  ),
                  if (enabled && food != null) ...[
                    const SizedBox(height: 16),
                    FoodBanner(
                        compact: true, onOrder: () => _openFood(food, 'FOOD')),
                    const SizedBox(height: 20),
                    SectionTitle(title: s.nearbyTitle),
                    const SizedBox(height: 8),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: FilterChip(
                        avatar: const Icon(Icons.tune_rounded, size: 18),
                        label: Text(s.catalogOpenOnly),
                        selected: _openOnly,
                        onSelected: (value) =>
                            setState(() => _openOnly = value),
                      ),
                    ),
                    FoodNearbySection(
                        services: food, query: _query, openOnly: _openOnly),
                  ],
                ] else if (state.hasError) ...[
                  EmptyStateCard(
                    icon: Icons.cloud_off_outlined,
                    title: s.offline,
                    body: s.retryHint,
                  ),
                  TextButton(
                    onPressed: () => setState(
                      () => _snapshot = widget.api.loadPlatformSnapshot(),
                    ),
                    child: Text(s.retry),
                  ),
                ] else
                  EmptyStateCard(
                    icon: Icons.search_off_rounded,
                    title: s.searchTabUnavailableTitle,
                    body: s.searchTabUnavailableBody,
                  ),
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
              body: s.ordersEmptyBody,
            ),
          ],
        ),
      ),
    );
  }
}
