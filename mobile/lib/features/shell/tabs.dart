import 'package:flutter/material.dart';

import '../../core/localization/kunde_localizations.dart';
import '../food/food_services.dart';
import '../food/presentation/food_home_screen.dart';
import '../home/data/kunde_api.dart';
import '../home/presentation/home_strings.dart';
import '../home/data/platform_snapshot.dart';
import '../home/presentation/catalog_search_panel.dart';
import '../home/presentation/super_app_widgets.dart';
import 'shell_strings.dart';
import '../booking/booking_services.dart';
import '../booking/presentation/services_home_screen.dart';

enum KundeTab { home, search, orders, services, profile }

class KundeNavigationBar extends StatelessWidget {
  const KundeNavigationBar(
      {required this.selected, required this.onSelected, super.key});

  final KundeTab selected;

  /// Null disables the bar (for example while a request is in flight).
  final ValueChanged<KundeTab>? onSelected;

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final labels = [
      s.navHome,
      s.navSearch,
      s.navOrders,
      s.navServices,
      s.navProfile
    ];
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
            text: label, style: labelStyle.copyWith(fontSize: fontSize)),
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
                label: s.navHome),
            NavigationDestination(
                icon: const Icon(Icons.search_rounded), label: s.navSearch),
            NavigationDestination(
                icon: const Icon(Icons.receipt_long_outlined),
                selectedIcon: const Icon(Icons.receipt_long_rounded),
                label: s.navOrders),
            NavigationDestination(
                icon: const Icon(Icons.grid_view_outlined),
                selectedIcon: const Icon(Icons.grid_view_rounded),
                label: s.navServices),
            NavigationDestination(
                icon: const Icon(Icons.person_outline),
                selectedIcon: const Icon(Icons.person_rounded),
                label: s.navProfile),
          ],
        ),
      ),
    );
  }
}

/// Uses the same server capability gate as the home category.
class ServicesTab extends StatefulWidget {
  const ServicesTab({required this.api, this.booking, super.key});
  final KundeApi api;
  final BookingServices? booking;

  @override
  State<ServicesTab> createState() => _ServicesTabState();
}

class _ServicesTabState extends State<ServicesTab> {
  late Future<PlatformSnapshot> _snapshot = widget.api.loadPlatformSnapshot();

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    return FutureBuilder<PlatformSnapshot>(
        future: _snapshot,
        builder: (context, state) {
          if (state.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.data?.bookingEnabled == true && widget.booking != null) {
            return ServicesHomeScreen(services: widget.booking!);
          }
          return ListView(padding: const EdgeInsets.all(20), children: [
            Text(s.navServices,
                style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 24),
            EmptyStateCard(
                icon: Icons.grid_view_rounded,
                title: state.hasError ? s.offline : s.servicesUnavailableTitle,
                body:
                    state.hasError ? s.retryHint : s.searchTabUnavailableBody),
            if (state.hasError)
              TextButton.icon(
                  onPressed: () => setState(
                      () => _snapshot = widget.api.loadPlatformSnapshot()),
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(s.retry)),
          ]);
        });
  }
}

/// Search tab: real catalog search when the server enables the marketplace,
/// otherwise an honest empty state.
class SearchTab extends StatefulWidget {
  const SearchTab({required this.api, this.food, this.booking, super.key});

  final KundeApi api;
  final FoodServices? food;
  final BookingServices? booking;

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
        final canBrowseBookings = done &&
            state.data?.bookingEnabled == true &&
            widget.booking != null;
        final food = widget.food;
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
                else if (enabled || canBrowseBookings) ...[
                  if (enabled) CatalogSearchPanel(api: widget.api),
                  if (enabled && food != null)
                    for (final (icon, label, vertical) in [
                      (Icons.restaurant_outlined, s.catFood, 'FOOD'),
                      (
                        Icons.shopping_basket_outlined,
                        s.catGroceries,
                        'GROCERY'
                      ),
                      (
                        Icons.local_florist_outlined,
                        s.catFlowers,
                        'FLOWERS_GIFTS'
                      ),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: QuickAction(
                          icon: icon,
                          label: label,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                                builder: (_) => FoodHomeScreen(
                                    services: food, vertical: vertical)),
                          ),
                        ),
                      ),
                  if (canBrowseBookings)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: QuickAction(
                        icon: Icons.event_available_outlined,
                        label: s.catServices,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                              builder: (_) => ServicesHomeScreen(
                                  services: widget.booking!)),
                        ),
                      ),
                    ),
                ] else if (state.hasError)
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
