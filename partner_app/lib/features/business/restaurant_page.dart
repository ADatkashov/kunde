import 'package:flutter/material.dart';

import '../../app/ops_store.dart';
import '../../core/error_text.dart';
import '../../core/format.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/partner_operations.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/states.dart';
import 'dish_sheet.dart';

/// Menu of one restaurant: availability for everyone with processing rights,
/// name/price/stock editing and adding dishes for Owner/Manager.
class RestaurantPage extends StatefulWidget {
  const RestaurantPage({
    required this.store,
    required this.restaurant,
    required this.canManage,
    super.key,
  });
  final OpsStore store;
  final Restaurant restaurant;
  final bool canManage;
  @override
  State<RestaurantPage> createState() => _RestaurantPageState();
}

class _RestaurantPageState extends State<RestaurantPage> {
  List<Dish>? _dishes;
  Object? _error;
  final Set<String> _busy = {};

  PartnerOperations get _ops => widget.store.ops;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await _ops.dishes(widget.restaurant.id);
      if (mounted) {
        setState(() {
          _dishes = rows;
          _error = null;
        });
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _toggle(Dish d, bool value) async {
    if (!_busy.add(d.id)) return;
    setState(() {});
    final s = S.of(context);
    try {
      final updated =
          await _ops.updateDish(widget.restaurant.id, d.id, available: value);
      if (mounted) {
        setState(() =>
            _dishes = [for (final x in _dishes!) x.id == d.id ? updated : x]);
      }
    } on Object catch (e) {
      if (mounted) showToast(context, errorText(s, e), error: true);
    } finally {
      _busy.remove(d.id);
      if (mounted) setState(() {});
    }
  }

  Future<void> _edit(Dish? dish) async {
    final sections = <String, String>{};
    for (final d in _dishes ?? const <Dish>[]) {
      if (d.sectionId != null) sections[d.sectionId!] = d.section;
    }
    final changed = await showDishSheet(
      context,
      ops: _ops,
      restaurantId: widget.restaurant.id,
      dish: dish,
      sections: sections,
    );
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final dishes = _dishes;
    return Scaffold(
      appBar: AppBar(title: Text(widget.restaurant.name)),
      floatingActionButton: widget.canManage && dishes != null
          ? FloatingActionButton.extended(
              onPressed: () => _edit(null),
              icon: const Icon(Icons.add_rounded),
              label: Text(s.addDish),
            )
          : null,
      body: dishes == null
          ? (_error != null
              ? ErrorView(error: _error!, onRetry: _load)
              : const SkeletonList(count: 4))
          : RefreshIndicator(
              onRefresh: _load,
              child: dishes.isEmpty
                  ? LayoutBuilder(
                      builder: (context, c) => ListView(children: [
                        SizedBox(
                          height: c.maxHeight,
                          child: MessageView(
                              icon: Icons.restaurant_menu_rounded,
                              title: s.menuEmpty,
                              body: widget.canManage ? s.dishNoSection : null),
                        ),
                      ]),
                    )
                  : _menu(context, dishes),
            ),
    );
  }

  Widget _menu(BuildContext context, List<Dish> dishes) {
    final s = S.of(context);
    final bySection = <String, List<Dish>>{};
    for (final d in dishes) {
      bySection.putIfAbsent(d.section, () => []).add(d);
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, 96),
      children: [
        if (!widget.canManage)
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.md),
            child: Text(s.ownerOnlyEdit,
                style: context.text.bodySmall
                    ?.copyWith(color: context.colors.onSurfaceVariant)),
          ),
        for (final entry in bySection.entries) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Gap.sm),
            child: Semantics(
                header: true,
                child: Text(entry.key, style: context.text.titleMedium)),
          ),
          for (final d in entry.value)
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.sm),
              child: Card(
                child: Padding(
                  padding:
                      const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.sm, Gap.sm),
                  child: Row(children: [
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(d.name, style: context.text.titleSmall),
                            const SizedBox(height: 2),
                            Text(
                              [
                                formatMoney(d.priceMinor),
                                if (d.stockQty != null)
                                  s.stockLeft(d.stockQty!),
                                d.available
                                    ? s.dishAvailable
                                    : s.dishUnavailable,
                              ].join(' · '),
                              style: context.text.bodySmall?.copyWith(
                                  color: context.colors.onSurfaceVariant),
                            ),
                          ]),
                    ),
                    if (widget.canManage)
                      IconButton(
                        tooltip: s.editDish,
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _edit(d),
                      ),
                    Semantics(
                      label:
                          '${d.name}: ${d.available ? s.dishAvailable : s.dishUnavailable}',
                      child: Switch(
                        value: d.available,
                        onChanged:
                            _busy.contains(d.id) ? null : (v) => _toggle(d, v),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
        ],
      ],
    );
  }
}
