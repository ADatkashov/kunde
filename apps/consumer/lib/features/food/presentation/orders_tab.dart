import 'package:flutter/material.dart';

import 'package:kunde_localization/kunde_localizations.dart';
import '../../home/presentation/home_strings.dart';
import '../../shell/shell_strings.dart';
import '../data/food_api.dart';
import 'package:kunde_models/food_models.dart';
import '../food_services.dart';
import 'food_widgets.dart';
import 'order_screen.dart';

/// Orders tab: history of the signed-in customer, restored from the server on every open.
class FoodOrdersTab extends StatefulWidget {
  const FoodOrdersTab(
      {required this.services, this.showHeading = true, super.key});

  final FoodServices services;
  final bool showHeading;

  @override
  State<FoodOrdersTab> createState() => _FoodOrdersTabState();
}

enum _OrderFilter { all, active, completed }

class _FoodOrdersTabState extends State<FoodOrdersTab> {
  late Future<List<FoodOrder>> _orders;
  _OrderFilter _filter = _OrderFilter.all;

  @override
  void initState() {
    super.initState();
    _orders = widget.services.api.orders();
  }

  Future<void> _refresh() async {
    final next = widget.services.api.orders();
    setState(() {
      _orders = next;
    });
    try {
      await next;
    } catch (_) {}
  }

  Future<void> _open(FoodOrder order) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OrderScreen(
          services: widget.services,
          orderId: order.id,
          initial: order,
        ),
      ),
    );
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: FutureBuilder<List<FoodOrder>>(
              future: _orders,
              builder: (context, state) {
                if (state.connectionState != ConnectionState.done) {
                  return const RestaurantListSkeleton(count: 2);
                }
                if (state.hasError) {
                  final error = state.error;
                  return FoodStateMessage(
                    icon: Icons.cloud_off_outlined,
                    title: 'Не удалось загрузить заказы',
                    body: error is FoodException ? error.message : null,
                    onAction: _refresh,
                  );
                }
                final s = KundeLocalizations.of(context);
                final all = state.data!;
                final orders = all
                    .where(
                      (order) => switch (_filter) {
                        _OrderFilter.all => true,
                        _OrderFilter.active => !order.terminal,
                        _OrderFilter.completed => order.terminal,
                      },
                    )
                    .toList();
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (widget.showHeading)
                        Text(
                          s.quickOrders,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final (filter, label) in [
                            (_OrderFilter.all, s.ordersAll),
                            (_OrderFilter.active, s.ordersActive),
                            (_OrderFilter.completed, s.ordersCompleted),
                          ])
                            ChoiceChip(
                              shape: const StadiumBorder(),
                              label: Text(label),
                              selected: _filter == filter,
                              onSelected: (_) =>
                                  setState(() => _filter = filter),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (orders.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 32),
                          child: Text(
                            all.isEmpty
                                ? s.ordersEmptyTitle
                                : s.ordersFilterEmpty,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      for (final order in orders)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _OrderCard(
                            order: order,
                            onTap: () => _open(order),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.onTap});

  final FoodOrder order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cancelled = order.status == 'CANCELLED';
    final done = order.status == 'DELIVERED';
    final colors = theme.colorScheme;
    final (chipColor, chipInk) = cancelled
        ? (colors.errorContainer, colors.onErrorContainer)
        : done
            ? (colors.tertiaryContainer, colors.onTertiaryContainer)
            : (colors.secondaryContainer, colors.onSecondaryContainer);
    final (asset, icon) = switch (order.vertical) {
      'GROCERY' => (
          'assets/photos/groceries.jpg',
          Icons.shopping_basket_outlined,
        ),
      'FLOWERS_GIFTS' => (null, Icons.local_florist_outlined),
      _ => ('assets/photos/food.jpg', Icons.restaurant_outlined),
    };
    return Card(
      margin: EdgeInsets.zero,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox.square(
                  dimension: 60,
                  child: asset == null
                      ? ColoredBox(
                          color: colors.primaryContainer,
                          child: Icon(icon, color: colors.onPrimaryContainer),
                        )
                      : Image.asset(
                          asset,
                          fit: BoxFit.cover,
                          excludeFromSemantics: true,
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.restaurantName,
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      formatOrderDate(order.placedAt),
                      style: theme.textTheme.bodySmall,
                    ),
                    Text(
                      order.items
                          .map((item) => '${item.quantity}× ${item.name}')
                          .join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: chipColor,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Text(
                            order.vertical == 'FLOWERS_GIFTS'
                                ? flowersStatusLabel(
                                    order.status,
                                    Localizations.localeOf(context)
                                        .languageCode,
                                  )
                                : orderStatusLabel(order.status,
                                    pickup: order.pickup),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: chipInk,
                            ),
                          ),
                        ),
                        Text(
                          formatTenge(
                            order.finalTotalMinor ?? order.totalMinor,
                          ),
                          style: theme.textTheme.titleSmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
