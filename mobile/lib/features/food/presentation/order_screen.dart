import 'dart:async';

import 'package:flutter/material.dart';

import '../data/cart_controller.dart';
import '../data/food_api.dart';
import '../data/food_models.dart';
import '../food_services.dart';
import 'cart_screen.dart';
import 'food_widgets.dart';

/// Order details with live status (polled until the order is finished), cancel and repeat.
class OrderScreen extends StatefulWidget {
  const OrderScreen(
      {required this.services,
      required this.orderId,
      this.initial,
      this.justPlaced = false,
      super.key});

  final FoodServices services;
  final String orderId;
  final FoodOrder? initial;
  final bool justPlaced;

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  FoodOrder? _order;
  String? _error;
  bool _busy = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _order = widget.initial;
    _load();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_order == null || !_order!.terminal) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final order = await widget.services.api.order(widget.orderId);
      if (!mounted) return;
      setState(() {
        _order = order;
        _error = null;
      });
    } on FoodException catch (error) {
      if (!mounted || silent && _order != null) return;
      setState(() => _error = error.message);
    }
  }

  Future<void> _cancel() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Отменить заказ?'),
        content: const Text(
            'Бесплатная отмена возможна, пока ресторан не принял заказ.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Нет')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Отменить заказ')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final order = await widget.services.api.cancel(widget.orderId);
      if (mounted) setState(() => _order = order);
    } on FoodException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
      _load(silent: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _repeat() async {
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await widget.services.api.repeat(widget.orderId);
      final menu = await widget.services.api.menu(result.restaurantId);
      final cart = widget.services.cart;
      cart.clear();
      for (final item in result.items) {
        final line = _lineFromMenu(menu, item);
        if (line != null) cart.add(menu.restaurant, line);
      }
      if (!mounted) return;
      if (cart.isEmpty) {
        messenger.showSnackBar(const SnackBar(
            content: Text('Блюда из этого заказа сейчас недоступны.')));
        return;
      }
      if (result.skipped.isNotEmpty) {
        messenger.showSnackBar(SnackBar(
            content:
                Text('Недоступно и пропущено: ${result.skipped.join(', ')}')));
      }
      nav.push(MaterialPageRoute<void>(
          builder: (_) => CartScreen(services: widget.services)));
    } on FoodException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  CartLine? _lineFromMenu(RestaurantMenu menu, RepeatItem item) {
    for (final section in menu.sections) {
      for (final dish in section.dishes) {
        if (dish.id != item.dishId) continue;
        final chosen = [
          for (final group in dish.optionGroups)
            for (final option in group.options)
              if (item.optionIds.contains(option.id)) option,
        ];
        return CartLine(
          dishId: dish.id,
          name: dish.name,
          emoji: dish.emoji,
          tone: dish.tone,
          optionIds: item.optionIds,
          optionsText: chosen.map((o) => o.name).join(', '),
          unitPriceMinor:
              dish.priceMinor + chosen.fold(0, (s, o) => s + o.priceDeltaMinor),
          quantity: item.quantity
              .clamp(1, dish.maxQuantity < 1 ? 1 : dish.maxQuantity),
          unit: dish.unit,
          maxQuantity: dish.maxQuantity,
          substitution: item.substitution,
          substituteDishIds: item.substituteDishIds,
        );
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    return Scaffold(
      appBar: AppBar(title: const Text('Заказ')),
      body: order == null
          ? (_error != null
              ? FoodStateMessage(
                  icon: Icons.cloud_off_outlined,
                  title: 'Не удалось загрузить заказ',
                  body: _error,
                  onAction: _load)
              : const Center(child: CircularProgressIndicator()))
          : RefreshIndicator(
              onRefresh: _load,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      children: _content(context, order)),
                ),
              ),
            ),
    );
  }

  List<Widget> _content(BuildContext context, FoodOrder order) {
    final theme = Theme.of(context);
    String tx(String ru, String kk, String en) {
      if (order.vertical != 'FLOWERS_GIFTS') return ru;
      return switch (Localizations.localeOf(context).languageCode) {
        'kk' => kk,
        'en' => en,
        _ => ru,
      };
    }

    return [
      if (widget.justPlaced && order.status == 'PLACED')
        Card(
          color: theme.colorScheme.primaryContainer,
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: const Icon(Icons.check_circle_rounded),
            title: Text(order.vertical == 'FLOWERS_GIFTS'
                ? switch (Localizations.localeOf(context).languageCode) {
                    'kk' => 'Сынақ тапсырыс жасалды',
                    'en' => 'Test order created',
                    _ => 'Тестовый заказ создан',
                  }
                : 'Заказ принят!'),
            subtitle: Text(order.vertical == 'FLOWERS_GIFTS'
                ? switch (Localizations.localeOf(context).languageCode) {
                    'kk' => 'Серіктестің жауабын күтіңіз.',
                    'en' => 'Waiting for the partner to respond.',
                    _ => 'Ожидайте ответа партнёра.',
                  }
                : 'Следите за статусом ниже. Он обновляется автоматически.'),
          ),
        ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
              tx(
                  'Нет связи, показаны последние данные.',
                  'Байланыс жоқ, соңғы деректер көрсетілді.',
                  'Offline: showing the most recent data.'),
              style: TextStyle(color: theme.colorScheme.error)),
        ),
      Text(order.restaurantName, style: theme.textTheme.headlineSmall),
      Text(
          '${tx('Оформлен', 'Рәсімделген', 'Placed')} ${formatOrderDate(order.placedAt)}',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      const SizedBox(height: 16),
      _StatusTimeline(order: order),
      const SizedBox(height: 8),
      Text(
          order.vertical == 'FLOWERS_GIFTS'
              ? switch (Localizations.localeOf(context).languageCode) {
                  'kk' =>
                    'Сынақ тапсырыс: төлем мен нақты жеткізу жоқ. Күйді серіктес өзгертеді.',
                  'en' =>
                    'Test order: no payment or real delivery. The partner updates the status.',
                  _ =>
                    'Тестовый заказ: оплаты и реальной доставки нет. Статусы меняет партнёр.',
                }
              : 'DEV-режим: приготовление и доставка имитируются по таймеру.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      const Divider(height: 32),
      Text(tx('Состав заказа', 'Тапсырыс құрамы', 'Order items'),
          style: theme.textTheme.titleLarge),
      const SizedBox(height: 8),
      for (final l in order.items) _OrderLineTile(line: l),
      if (order.hasChanges)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Material(
            color: theme.colorScheme.tertiaryContainer,
            borderRadius: BorderRadius.circular(12),
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                  'Магазин изменил заказ: часть товаров заменена по вашему выбору '
                  'или убрана, так как их не оказалось. Сумма пересчитана.'),
            ),
          ),
        ),
      const Divider(height: 24),
      _kv(tx('Блюда', 'Тауарлар', 'Items'), formatTenge(order.subtotalMinor)),
      _kv(
          tx('Доставка', 'Жеткізу', 'Delivery'),
          order.deliveryFeeMinor == 0
              ? tx('Бесплатно', 'Тегін', 'Free')
              : formatTenge(order.deliveryFeeMinor)),
      if (order.finalTotalMinor != null &&
          order.finalTotalMinor != order.totalMinor) ...[
        _kv(tx('Было', 'Бұрын', 'Original'), formatTenge(order.totalMinor)),
        _kv(
            tx('Итого с учётом изменений', 'Өзгерістермен барлығы',
                'Total after changes'),
            formatTenge(order.finalTotalMinor!),
            bold: true),
      ] else
        _kv(tx('Итого', 'Барлығы', 'Total'), formatTenge(order.totalMinor),
            bold: true),
      const Divider(height: 32),
      ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.location_on_outlined),
          title: Text(order.addressLabel),
          subtitle: Text(order.addressText)),
      ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.payments_outlined),
          title: Text(tx('Оплата', 'Төлем', 'Payment')),
          subtitle: Text(order.paymentMethod == 'DEV_NO_PAYMENT'
              ? switch (Localizations.localeOf(context).languageCode) {
                  'kk' => 'Сынақ тапсырыс — төлемсіз',
                  'en' => 'Test order — no payment',
                  _ => 'Тестовый заказ — без оплаты',
                }
              : order.paymentLabel)),
      if (order.comment != null)
        ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.chat_bubble_outline_rounded),
            title: Text(tx('Комментарий', 'Түсініктеме', 'Note')),
            subtitle: Text(order.comment!)),
      const SizedBox(height: 16),
      if (order.cancellable)
        OutlinedButton.icon(
          onPressed: _busy ? null : _cancel,
          icon: const Icon(Icons.close_rounded),
          label: Text(
              tx('Отменить заказ', 'Тапсырыстан бас тарту', 'Cancel order')),
        ),
      if (order.terminal) ...[
        FilledButton.icon(
          onPressed: _busy ? null : _repeat,
          icon: const Icon(Icons.replay_rounded),
          label:
              Text(tx('Повторить заказ', 'Тапсырысты қайталау', 'Order again')),
        ),
      ],
      if (!order.cancellable && !order.terminal)
        Text(
            tx(
                'Ресторан принял заказ — отмена через приложение недоступна.',
                'Серіктес тапсырысты қабылдады — қолданба арқылы бас тарту мүмкін емес.',
                'The partner accepted the order; cancellation in the app is unavailable.'),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    ];
  }

  Widget _kv(String label, String value, {bool bold = false}) {
    final style = bold
        ? Theme.of(context).textTheme.titleLarge
        : Theme.of(context).textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Expanded(child: Text(label, style: style)),
        Text(value, style: style)
      ]),
    );
  }
}

class _StatusTimeline extends StatelessWidget {
  const _StatusTimeline({required this.order});

  final FoodOrder order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (order.status == 'CANCELLED') {
      return Material(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
        child: ListTile(
          leading: const Icon(Icons.cancel_outlined),
          title: Text(order.cancelReason == 'PARTNER_TIMEOUT'
              ? 'Заведение не ответило вовремя'
              : order.cancelledBy == 'PARTNER'
                  ? 'Заказ отклонён заведением'
                  : 'Заказ отменён'),
          subtitle: Text(order.paymentMethod == 'DEV_NO_PAYMENT'
              ? switch (Localizations.localeOf(context).languageCode) {
                  'kk' =>
                    '${order.cancelReason != null && order.cancelledBy == 'PARTNER' ? 'Себебі: ${order.cancelReason}\n' : ''}Төлем жүргізілген жоқ.',
                  'en' =>
                    '${order.cancelReason != null && order.cancelledBy == 'PARTNER' ? 'Reason: ${order.cancelReason}\n' : ''}No payment was made.',
                  _ =>
                    '${order.cancelReason != null && order.cancelledBy == 'PARTNER' ? 'Причина: ${order.cancelReason}\n' : ''}Оплата не производилась.',
                }
              : order.cancelReason != null && order.cancelledBy == 'PARTNER'
                  ? 'Причина: ${order.cancelReason}\nПлатёж аннулирован.'
                  : 'Платёж аннулирован.'),
        ),
      );
    }
    final current = orderFlow.indexOf(order.status);
    final label = order.vertical == 'FLOWERS_GIFTS'
        ? flowersStatusLabel(
            order.status, Localizations.localeOf(context).languageCode)
        : orderStatusLabel(order.status);
    return Semantics(
      container: true,
      label: label,
      child: Column(children: [
        for (var i = 0; i < orderFlow.length; i++)
          _step(
              context,
              i,
              current,
              order.timeline
                  .where((e) => e.status == orderFlow[i])
                  .firstOrNull),
      ]),
    );
  }

  Widget _step(
      BuildContext context, int index, int current, TimelineEntry? entry) {
    final theme = Theme.of(context);
    final done = index < current ||
        (index == current && orderFlow[index] == 'DELIVERED');
    final active = index == current && !done;
    final color =
        done || active ? theme.colorScheme.primary : theme.colorScheme.outline;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 32,
          child: Column(children: [
            Icon(
                done
                    ? Icons.check_circle_rounded
                    : active
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                color: color,
                size: 24),
            if (index < orderFlow.length - 1)
              Expanded(
                  child: Container(
                      width: 2,
                      color: done ? color : theme.colorScheme.outlineVariant)),
          ]),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(children: [
              Expanded(
                child: Text(
                    order.vertical == 'FLOWERS_GIFTS'
                        ? flowersStatusLabel(orderFlow[index],
                            Localizations.localeOf(context).languageCode)
                        : orderStatusLabel(orderFlow[index]),
                    style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                        color: done || active
                            ? null
                            : theme.colorScheme.onSurfaceVariant)),
              ),
              if (entry != null)
                Text(formatOrderDate(entry.at.toLocal()),
                    style: theme.textTheme.bodySmall),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// One order line: quantity with unit, and what the store did with it once it collected the order.
class _OrderLineTile extends StatelessWidget {
  const _OrderLineTile({required this.line});

  final OrderLine line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final removed = line.fulfillmentStatus == 'REMOVED';
    final replaced = line.fulfillmentStatus == 'SUBSTITUTED';
    final qty = formatQuantity(line.unit, line.quantity);
    final title = '$qty${line.unit == 'KG' ? ' ' : ' × '}${line.name}';
    final strike = removed || replaced;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: Text(
                  '$title${line.optionsText.isEmpty ? '' : '\n${line.optionsText}'}',
                  style: strike
                      ? const TextStyle(decoration: TextDecoration.lineThrough)
                      : null)),
          Text(formatTenge(line.lineTotalMinor),
              style: strike
                  ? const TextStyle(decoration: TextDecoration.lineThrough)
                  : null),
        ]),
        if (replaced)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(children: [
              Icon(Icons.swap_horiz_rounded,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                  child: Text('Заменено на: ${line.replacedByName}',
                      style: TextStyle(color: theme.colorScheme.primary))),
              Text(formatTenge(line.finalLineTotalMinor ?? 0)),
            ]),
          ),
        if (removed)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('Нет в наличии — убрано из заказа',
                style: TextStyle(color: theme.colorScheme.error)),
          ),
      ]),
    );
  }
}
