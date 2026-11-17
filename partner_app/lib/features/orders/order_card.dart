import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../widgets/header_row.dart';
import '../../widgets/now_builder.dart';
import '../../widgets/status_chip.dart';

/// Primary (forward) and destructive (reject) actions of an order, derived
/// from the server-provided `allowedNext`.
class OrderActionBar extends StatelessWidget {
  const OrderActionBar({
    required this.order,
    required this.busy,
    required this.onAction,
    super.key,
  });
  final PartnerOrder order;
  final bool busy;
  final void Function(String status) onAction;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final forward = order.allowedNext.where((x) => x != 'CANCELLED').toList();
    final canReject = order.allowedNext.contains('CANCELLED');
    if (forward.isEmpty && !canReject) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: Gap.md),
      child: Wrap(spacing: Gap.sm, runSpacing: Gap.sm, children: [
        for (final next in forward)
          FilledButton(
            onPressed: busy ? null : () => onAction(next),
            child: busy
                ? Row(mainAxisSize: MainAxisSize.min, children: [
                    const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: Gap.sm),
                    Text(s.orderBusy),
                  ])
                : Text(s.orderAction(next)),
          ),
        if (canReject)
          OutlinedButton(
            style: OutlinedButton.styleFrom(
                foregroundColor: context.colors.error,
                side: BorderSide(
                    color: context.colors.error.withValues(alpha: 0.6))),
            onPressed: busy ? null : () => onAction('CANCELLED'),
            child: Text(s.orderAction('CANCELLED')),
          ),
      ]),
    );
  }
}

/// Countdown line for a new order waiting for the partner's answer.
class ResponseDeadline extends StatelessWidget {
  const ResponseDeadline({required this.order, super.key});
  final PartnerOrder order;

  @override
  Widget build(BuildContext context) {
    final deadline = order.respondBy;
    if (!order.isNew || deadline == null) return const SizedBox.shrink();
    final s = S.of(context);
    return NowBuilder(builder: (context, now) {
      final left = minutesLeft(deadline, now);
      final over = !deadline.isAfter(now);
      final urgent = over || left <= 2;
      final tones = context.tones;
      final color = urgent ? context.colors.error : tones.warning;
      final text = over
          ? s.replyOverdue
          : '${s.replyBy(formatTime(deadline))} · ${s.minutesLeftText(left)}';
      return Padding(
        padding: const EdgeInsets.only(top: Gap.sm),
        child: Row(children: [
          Icon(Icons.timer_outlined, size: 18, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: context.text.labelLarge?.copyWith(color: color)),
          ),
        ]),
      );
    });
  }
}

class OrderCard extends StatelessWidget {
  const OrderCard({
    required this.order,
    required this.busy,
    required this.onOpen,
    required this.onAction,
    super.key,
  });
  final PartnerOrder order;
  final bool busy;
  final VoidCallback onOpen;
  final void Function(String status) onAction;

  String _summary(S s) {
    if (order.items.isEmpty) return s.noItemsInfo;
    final first = order.items.take(2).map((l) => '${l.quantity}× ${l.name}');
    final rest = order.items.length - 2;
    return rest > 0 ? '${first.join(', ')} +$rest' : first.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final locale = Localizations.localeOf(context);
    final placed = order.placedAt;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(Gap.lg),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            HeaderRow(
              leading: Text(s.orderNumber(order.shortRef),
                  style: context.text.titleMedium),
              trailing: StatusChip(
                  label: s.orderStatus(order.status),
                  tone: orderTone(order.status)),
            ),
            if (placed != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: NowBuilder(
                  builder: (_, now) => Text(
                    '${formatDateTime(placed, locale)} · ${s.agoMinutes(now.difference(placed).inMinutes)}',
                    style: context.text.bodySmall
                        ?.copyWith(color: context.colors.onSurfaceVariant),
                  ),
                ),
              ),
            const SizedBox(height: Gap.md),
            Text(_summary(s),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.text.bodyLarge),
            const SizedBox(height: Gap.sm),
            Wrap(
              spacing: Gap.md,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(formatMoney(order.totalMinor, currency: order.currency),
                    style: context.text.titleMedium?.copyWith(
                        color: context.colors.primary,
                        fontWeight: FontWeight.w700)),
                if (order.itemCount > 0)
                  Text(s.itemsCount(order.itemCount),
                      style: context.text.bodySmall
                          ?.copyWith(color: context.colors.onSurfaceVariant)),
              ],
            ),
            ResponseDeadline(order: order),
            if (order.status == 'CANCELLED' && order.cancelReason != null)
              Padding(
                padding: const EdgeInsets.only(top: Gap.sm),
                child: Text(
                    '${s.cancelReasonTitle}: ${s.reasonText(order.cancelReason!)}',
                    style: context.text.bodySmall
                        ?.copyWith(color: context.colors.onSurfaceVariant)),
              ),
            OrderActionBar(order: order, busy: busy, onAction: onAction),
          ]),
        ),
      ),
    );
  }
}
