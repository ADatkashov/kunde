import 'package:flutter/material.dart';

import '../../app/ops_store.dart';
import '../../core/format.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../widgets/header_row.dart';
import '../../widgets/status_chip.dart';
import '../../core/error_text.dart';
import '../../widgets/dialogs.dart';
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
                              if (l.itemId != null &&
                                  l.fulfillmentStatus != 'PENDING')
                                Text(
                                    l.fulfillmentStatus == 'PROPOSED'
                                        ? '${s.pickStatus('PROPOSED')}: ${l.proposedName ?? ''}'
                                        : l.fulfillmentStatus == 'SUBSTITUTED'
                                            ? '${s.pickStatus('SUBSTITUTED')}: ${l.replacedByName ?? ''}'
                                            : s.pickStatus(l.fulfillmentStatus),
                                    style: muted),
                              if (order.status == 'PREPARING' &&
                                  l.itemId != null &&
                                  l.fulfillmentStatus == 'PENDING')
                                _PickRow(order: order, line: l, store: store),
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
            row(order.pickup ? s.pickupLabel : s.delivery,
                formatMoney(order.deliveryFeeMinor, currency: order.currency)),
            if (order.discountMinor > 0)
              row('${s.discountLabel}${order.promoCode == null ? '' : ' (${order.promoCode})'}',
                  '−${formatMoney(order.discountMinor, currency: order.currency)}'),
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

/// Per-line picking while the order is prepared: picked, missing or replace. The server decides whether a replacement
/// needs the customer's answer (it does unless the customer pre-approved it).
class _PickRow extends StatelessWidget {
  const _PickRow(
      {required this.order, required this.line, required this.store});

  final PartnerOrder order;
  final OrderLine line;
  final OpsStore store;

  Future<void> _run(BuildContext context, String action,
      {String? dishId}) async {
    final s = S.of(context);
    try {
      await store.pickLine(order.id, line.itemId!, action,
          replacementDishId: dishId);
    } on Object catch (e) {
      if (context.mounted) showToast(context, errorText(s, e), error: true);
    }
  }

  Future<void> _replace(BuildContext context) async {
    final s = S.of(context);
    final restaurantId = order.restaurantId;
    if (restaurantId == null) return;
    List<Dish> options;
    try {
      options = (await store.ops.dishes(restaurantId))
          .where((d) =>
              d.available &&
              d.id != line.dishId &&
              (d.unit == (line.unit ?? 'PIECE')) &&
              (d.stockQty == null || d.stockQty! > 0))
          .toList();
    } on Object catch (e) {
      if (context.mounted) showToast(context, errorText(s, e), error: true);
      return;
    }
    if (!context.mounted) return;
    final chosen = await showModalBottomSheet<Dish>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.lg),
          children: [
            Text(s.pickChooseReplacement, style: context.text.titleMedium),
            const SizedBox(height: Gap.sm),
            if (options.isEmpty) Text(s.pickNoAlternatives),
            for (final d in options)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(d.name),
                trailing: Text(formatMoney(d.priceMinor)),
                onTap: () => Navigator.pop(context, d),
              ),
          ],
        ),
      ),
    );
    if (chosen != null && context.mounted) {
      await _run(context, 'REPLACE', dishId: chosen.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final busy = store.isBusy(order.id);
    return Padding(
      padding: const EdgeInsets.only(top: Gap.sm),
      child: Wrap(spacing: Gap.sm, runSpacing: Gap.sm, children: [
        FilledButton.tonal(
            onPressed: busy ? null : () => _run(context, 'PICKED'),
            child: Text(s.pickDone)),
        OutlinedButton(
            onPressed: busy ? null : () => _run(context, 'MISSING'),
            child: Text(s.pickMissing)),
        OutlinedButton(
            onPressed: busy ? null : () => _replace(context),
            child: Text(s.pickReplace)),
      ]),
    );
  }
}
