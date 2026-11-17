import 'package:flutter/material.dart';

import '../../app/ops_store.dart';
import '../../core/format.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../widgets/header_row.dart';
import '../../widgets/status_chip.dart';
import 'order_actions.dart';
import 'order_card.dart';

/// Full order card. Reads the order from the store by id so that it follows
/// refreshes and status changes made from this page.
class OrderDetailsPage extends StatelessWidget {
  const OrderDetailsPage(
      {required this.store, required this.orderId, super.key});
  final OpsStore store;
  final String orderId;

  PartnerOrder? _find() {
    for (final list in [store.activeOrders.data, store.historyOrders.data]) {
      for (final o in list ?? const <PartnerOrder>[]) {
        if (o.id == orderId) return o;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final order = _find();
        return Scaffold(
          appBar: AppBar(
              title: Text(order == null
                  ? s.orderDetails
                  : s.orderNumber(order.shortRef))),
          body: order == null
              ? const SizedBox.shrink()
              : _Body(order: order, store: store),
          bottomNavigationBar: order == null || order.allowedNext.isEmpty
              ? null
              : SafeArea(
                  child: Padding(
                    padding:
                        const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.md),
                    child: Row(children: [
                      Flexible(
                        child: OrderActionBar(
                          order: order,
                          busy: store.isBusy(order.id),
                          onAction: (status) =>
                              performOrderAction(context, store, order, status),
                        ),
                      ),
                    ]),
                  ),
                ),
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.order, required this.store});
  final PartnerOrder order;
  final OpsStore store;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final locale = Localizations.localeOf(context);
    final text = context.text;
    final muted =
        text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant);
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 4, child: Text(label, style: muted)),
            Expanded(
                flex: 6,
                child: Text(value,
                    textAlign: TextAlign.end, style: text.bodyMedium)),
          ]),
        );
    return ListView(padding: const EdgeInsets.all(Gap.lg), children: [
      HeaderRow(
        leading: StatusChip(
            label: s.orderStatus(order.status), tone: orderTone(order.status)),
        trailing: Text(formatMoney(order.totalMinor, currency: order.currency),
            style: text.headlineSmall?.copyWith(
                color: context.colors.primary, fontWeight: FontWeight.w700)),
      ),
      ResponseDeadline(order: order),
      const SizedBox(height: Gap.lg),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(Gap.lg),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.orderItems, style: text.titleMedium),
            const SizedBox(height: Gap.sm),
            if (order.items.isEmpty) Text(s.noItemsInfo, style: muted),
            for (final l in order.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                          width: 40,
                          child: Text('${l.quantity}×',
                              style: text.titleSmall
                                  ?.copyWith(color: context.colors.primary))),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l.name, style: text.bodyLarge),
                              if (l.optionsText != null)
                                Text(l.optionsText!, style: muted),
                            ]),
                      ),
                      Text(
                          formatMoney(l.lineTotalMinor,
                              currency: order.currency),
                          style: text.bodyMedium),
                    ]),
              ),
            const Divider(height: Gap.xl),
            row(s.subtotal,
                formatMoney(order.subtotalMinor, currency: order.currency)),
            row(s.delivery,
                formatMoney(order.deliveryFeeMinor, currency: order.currency)),
            row(s.total,
                formatMoney(order.totalMinor, currency: order.currency)),
          ]),
        ),
      ),
      const SizedBox(height: Gap.md),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(Gap.lg),
          child: Column(children: [
            if (order.placedAt != null)
              row(s.orderPlacedAt, formatDateTime(order.placedAt!, locale)),
            row(s.orderPayment, s.paymentMethod(order.paymentMethod)),
            if (order.addressText != null)
              row(s.orderAddress, order.addressText!),
            if (order.comment != null) row(s.orderComment, order.comment!),
            if (order.cancelReason != null)
              row(s.cancelReasonTitle, s.reasonText(order.cancelReason!)),
          ]),
        ),
      ),
      if (order.timeline.isNotEmpty) ...[
        const SizedBox(height: Gap.md),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Gap.lg),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.history, style: text.titleMedium),
              const SizedBox(height: Gap.sm),
              for (final e in order.timeline)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.circle,
                            size: 10, color: context.colors.primary),
                        const SizedBox(width: Gap.sm),
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    '${s.orderStatus(e.status)} · ${s.actorName(e.actor)}',
                                    style: text.bodyMedium),
                                if (e.at != null)
                                  Text(formatDateTime(e.at!, locale),
                                      style: text.bodySmall?.copyWith(
                                          color:
                                              context.colors.onSurfaceVariant)),
                                if (e.reason != null)
                                  Text(s.reasonText(e.reason!),
                                      style: text.bodySmall),
                              ]),
                        ),
                      ]),
                ),
            ]),
          ),
        ),
      ],
    ]);
  }
}
