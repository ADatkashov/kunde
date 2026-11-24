import 'package:flutter/material.dart';

import '../../app/ops_store.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../widgets/states.dart';
import 'order_actions.dart';
import 'order_card.dart';
import 'order_details_page.dart';

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({required this.store, super.key});
  final OpsStore store;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final active = store.activeOrders.data ?? const <PartnerOrder>[];
        final fresh = active.where((o) => o.isNew).toList();
        final progress = active.where((o) => !o.isNew).toList();
        return DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: AppBar(
              title: Text(s.navOrders),
              bottom: TabBar(tabs: [
                Tab(child: _TabLabel(s.tabNew, fresh.length)),
                Tab(child: _TabLabel(s.tabInProgress, progress.length)),
                Tab(text: s.tabCompleted),
              ]),
            ),
            body: Column(children: [
              if (store.activeOrders.error != null &&
                  store.activeOrders.hasData)
                StaleBanner(error: store.activeOrders.error!),
              Expanded(
                child: TabBarView(children: [
                  _OrderList(
                    store: store,
                    slot: store.activeOrders,
                    orders: fresh,
                    emptyIcon: Icons.notifications_none_rounded,
                    emptyTitle: s.ordersEmptyNewTitle,
                    emptyBody: s.ordersEmptyNewBody,
                    onRefresh: store.refreshActiveOrders,
                  ),
                  _OrderList(
                    store: store,
                    slot: store.activeOrders,
                    orders: progress,
                    emptyIcon: Icons.soup_kitchen_outlined,
                    emptyTitle: s.ordersEmptyProgressTitle,
                    emptyBody: s.ordersEmptyProgressBody,
                    onRefresh: store.refreshActiveOrders,
                  ),
                  _OrderList(
                    store: store,
                    slot: store.historyOrders,
                    orders: store.historyOrders.data ?? const [],
                    emptyIcon: Icons.task_alt_rounded,
                    emptyTitle: s.ordersEmptyDoneTitle,
                    emptyBody: s.ordersEmptyDoneBody,
                    onRefresh: store.refreshOrderHistory,
                    history: true,
                  ),
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel(this.label, this.count);
  final String label;
  final int count;
  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        if (count > 0) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
              color: context.colors.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$count',
                style: context.text.labelSmall
                    ?.copyWith(color: context.colors.onPrimary)),
          ),
        ],
      ]);
}

class _OrderList extends StatelessWidget {
  const _OrderList({
    required this.store,
    required this.slot,
    required this.orders,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyBody,
    required this.onRefresh,
    this.history = false,
  });
  final OpsStore store;
  final Loadable<List<PartnerOrder>> slot;
  final List<PartnerOrder> orders;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyBody;
  final Future<void> Function() onRefresh;
  final bool history;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    if (!slot.hasData) {
      if (slot.failedWithoutData) {
        return ErrorView(error: slot.error!, onRetry: onRefresh);
      }
      return const SkeletonList();
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: orders.isEmpty
          ? LayoutBuilder(
              builder: (context, c) => ListView(children: [
                SizedBox(
                  height: c.maxHeight,
                  child: MessageView(
                      icon: emptyIcon, title: emptyTitle, body: emptyBody),
                ),
              ]),
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(Gap.lg),
              itemCount: orders.length +
                  (history && store.orderHistoryHasMore ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(height: Gap.md),
              itemBuilder: (context, i) {
                if (i >= orders.length) {
                  return Center(
                    child: store.loadingMoreOrders
                        ? const CircularProgressIndicator()
                        : OutlinedButton(
                            onPressed: store.loadMoreOrderHistory,
                            child: Text(s.loadMore)),
                  );
                }
                final o = orders[i];
                return OrderCard(
                  order: o,
                  busy: store.isBusy(o.id),
                  onOpen: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) =>
                              OrderDetailsPage(store: store, orderId: o.id))),
                  onAction: (status) =>
                      performOrderAction(context, store, o, status),
                );
              },
            ),
    );
  }
}
