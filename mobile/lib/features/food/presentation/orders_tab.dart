import 'package:flutter/material.dart';

import '../../../core/localization/kunde_localizations.dart';
import '../../home/presentation/home_strings.dart';
import '../data/food_api.dart';
import '../data/food_models.dart';
import '../food_services.dart';
import 'food_home_screen.dart';
import 'food_widgets.dart';
import 'order_screen.dart';
import '../../../shared/theme/kunde_art.dart';

/// Orders tab: history of the signed-in customer, restored from the server on every open.
class FoodOrdersTab extends StatefulWidget {
  const FoodOrdersTab({required this.services, super.key});

  final FoodServices services;

  @override
  State<FoodOrdersTab> createState() => _FoodOrdersTabState();
}

class _FoodOrdersTabState extends State<FoodOrdersTab> {
  late Future<List<FoodOrder>> _orders;

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
                final orders = state.data!;
                if (orders.isEmpty) {
                  return FoodStateMessage(
                    icon: Icons.receipt_long_outlined,
                    title: 'Заказов пока нет',
                    body:
                        'Выберите ресторан и оформите первый заказ — он появится здесь.',
                    actionLabel: 'Выбрать ресторан',
                    onAction: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            FoodHomeScreen(services: widget.services),
                      ),
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: orders.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      if (i == 0) {
                        return Text(
                          KundeLocalizations.of(context).quickOrders,
                          style: Theme.of(context).textTheme.headlineSmall,
                        );
                      }
                      return _OrderCard(
                        order: orders[i - 1],
                        onTap: () => _open(orders[i - 1]),
                      );
                    },
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
    final summary =
        order.items.map((e) => '${e.quantity}× ${e.name}').join(', ');
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
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  KundeIllustration(
                    order.vertical == 'FLOWERS_GIFTS'
                        ? 'beauty'
                        : order.vertical == 'GROCERY'
                            ? 'grocery'
                            : 'food',
                    size: 38,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      order.restaurantName,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: chipColor,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  order.vertical == 'FLOWERS_GIFTS'
                      ? flowersStatusLabel(
                          order.status,
                          Localizations.localeOf(context).languageCode,
                        )
                      : orderStatusLabel(order.status),
                  style: TextStyle(
                    color: chipInk,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text(
                    formatOrderDate(order.placedAt),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    formatTenge(order.totalMinor),
                    style: theme.textTheme.titleSmall,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
