import 'package:flutter/material.dart';

import '../../app/ops_store.dart';
import '../../core/error_text.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/states.dart';
import '../../widgets/status_chip.dart';
import 'restaurant_page.dart';
import 'venue_page.dart';

/// Business tab: the partner's restaurants and service venues with their open
/// state, leading to menu/price and service/schedule management.
class BusinessScreen extends StatelessWidget {
  const BusinessScreen(
      {required this.store, required this.canManage, super.key});
  final OpsStore store;

  /// Owner/Manager may toggle the open state, edit prices and schedules.
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.navBusiness)),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final r = store.restaurants;
          final v = store.venues;
          if (!r.hasData && !v.hasData) {
            if (r.failedWithoutData && v.failedWithoutData) {
              return ErrorView(error: r.error!, onRetry: store.refreshModules);
            }
            return const SkeletonList(count: 2);
          }
          final restaurants = r.data ?? const <Restaurant>[];
          final venues = v.data ?? const <Venue>[];
          return RefreshIndicator(
            onRefresh: store.refreshModules,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(Gap.lg),
              children: [
                if (restaurants.isNotEmpty) _Section(s.restaurantsTitle),
                for (final x in restaurants)
                  _Tile(
                    icon: Icons.restaurant_rounded,
                    name: x.name,
                    open: x.open,
                    openLabel: s.openForOrders,
                    canManage: canManage,
                    onToggle: (v) => _toggle(
                        context, () => store.ops.setRestaurantOpen(x.id, v)),
                    onOpen: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) => RestaurantPage(
                                store: store,
                                restaurant: x,
                                canManage: canManage))),
                  ),
                if (venues.isNotEmpty) _Section(s.venuesTitle),
                for (final x in venues)
                  _Tile(
                    icon: Icons.content_cut_rounded,
                    name: x.name,
                    open: x.open,
                    openLabel: s.openForBookings,
                    canManage: canManage,
                    onToggle: (v) =>
                        _toggle(context, () => store.ops.setVenueOpen(x.id, v)),
                    onOpen: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) => VenuePage(
                                store: store, venue: x, canManage: canManage))),
                  ),
                if (restaurants.isEmpty && venues.isEmpty)
                  SizedBox(
                    height: 360,
                    child: MessageView(
                        icon: Icons.storefront_outlined,
                        title: s.businessEmptyTitle,
                        body: s.businessEmptyBody),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _toggle(
      BuildContext context, Future<Object?> Function() call) async {
    final s = S.of(context);
    try {
      await call();
      await store.refreshModules();
    } on Object catch (e) {
      if (context.mounted) showToast(context, errorText(s, e), error: true);
    }
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: Gap.sm, bottom: Gap.md),
        child: Semantics(
            header: true, child: Text(title, style: context.text.titleMedium)),
      );
}

class _Tile extends StatefulWidget {
  const _Tile({
    required this.icon,
    required this.name,
    required this.open,
    required this.openLabel,
    required this.canManage,
    required this.onToggle,
    required this.onOpen,
  });
  final IconData icon;
  final String name;
  final bool open;
  final String openLabel;
  final bool canManage;
  final Future<void> Function(bool value) onToggle;
  final VoidCallback onOpen;
  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onOpen,
          child: Padding(
            padding: const EdgeInsets.all(Gap.lg),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(widget.icon, color: context.colors.primary),
                const SizedBox(width: Gap.md),
                Expanded(
                    child: Text(widget.name, style: context.text.titleMedium)),
                const Icon(Icons.chevron_right_rounded),
              ]),
              const SizedBox(height: Gap.sm),
              if (widget.canManage)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(widget.openLabel),
                  subtitle: Text(widget.open ? s.openNow : s.closedNow),
                  value: widget.open,
                  onChanged: _busy
                      ? null
                      : (v) async {
                          setState(() => _busy = true);
                          try {
                            await widget.onToggle(v);
                          } finally {
                            if (mounted) setState(() => _busy = false);
                          }
                        },
                )
              else
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: StatusChip(
                      label: widget.open ? s.openNow : s.closedNow,
                      tone: widget.open ? Tone.success : Tone.neutral),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
