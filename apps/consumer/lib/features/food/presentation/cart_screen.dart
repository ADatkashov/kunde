import 'package:flutter/material.dart';

import '../data/cart_controller.dart';
import '../data/food_api.dart';
import 'package:kunde_models/food_models.dart';
import '../food_services.dart';
import 'checkout_screen.dart';
import 'food_widgets.dart';

/// Cart: lines with quantity controls and a server-side price quote.
class CartScreen extends StatefulWidget {
  const CartScreen({required this.services, super.key});

  final FoodServices services;

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  Future<FoodQuote>? _quote;

  CartController get _cart => widget.services.cart;

  String _tx(String ru, String kk, String en) {
    if (_cart.restaurant?.vertical != 'FLOWERS_GIFTS') return ru;
    return switch (Localizations.localeOf(context).languageCode) {
      'kk' => kk,
      'en' => en,
      _ => ru,
    };
  }

  @override
  void initState() {
    super.initState();
    _cart.addListener(_changed);
    _requote();
  }

  @override
  void dispose() {
    _cart.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    _requote();
  }

  void _requote() {
    final restaurant = _cart.restaurant;
    setState(() {
      _quote = restaurant == null || _cart.isEmpty
          ? null
          : widget.services.api.quote(
              restaurant.id, [for (final l in _cart.lines) l.toRequest()]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final restaurant = _cart.restaurant;
    return Scaffold(
      appBar: AppBar(title: Text(_tx('Корзина', 'Себет', 'Cart')), actions: [
        if (!_cart.isEmpty)
          TextButton(
              onPressed: _cart.clear,
              child: Text(_tx('Очистить', 'Тазалау', 'Clear'))),
      ]),
      body: _cart.isEmpty || restaurant == null
          ? FoodStateMessage(
              icon: Icons.shopping_bag_outlined,
              title: 'Корзина пуста',
              body: 'Добавьте блюда из ресторана, чтобы оформить заказ.',
              actionLabel: 'Выбрать ресторан',
              onAction: () => Navigator.of(context).maybePop())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      OrderProgressHeader(
                          checkout: false,
                          flowers: restaurant.vertical == 'FLOWERS_GIFTS'),
                      Text(restaurant.name, style: theme.textTheme.titleLarge),
                      const SizedBox(height: 8),
                      for (final line in _cart.lines)
                        _LineTile(line: line, cart: _cart),
                      const Divider(height: 32),
                      FutureBuilder<FoodQuote>(
                        future: _quote,
                        builder: (context, state) =>
                            _totals(context, restaurant, state),
                      ),
                    ]),
              ),
            ),
    );
  }

  Widget _totals(BuildContext context, Restaurant restaurant,
      AsyncSnapshot<FoodQuote> state) {
    final theme = Theme.of(context);
    final preview = _cart.previewSubtotalMinor;
    final belowMin = preview < restaurant.minOrderMinor;
    if (state.connectionState != ConnectionState.done) {
      return const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()));
    }
    if (state.hasError) {
      final error = state.error;
      final failure =
          error is FoodException ? error.failure : FoodFailure.other;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Material(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Text(error is FoodException
                ? (restaurant.vertical == 'FLOWERS_GIFTS'
                    ? error.messageFor(
                        Localizations.localeOf(context).languageCode)
                    : error.message)
                : FoodException(FoodFailure.other).message),
          ),
        ),
        const SizedBox(height: 12),
        if (failure == FoodFailure.offline || failure == FoodFailure.other)
          OutlinedButton(
              onPressed: _requote,
              child: Text(
                  _tx('Обновить цены', 'Бағаларды жаңарту', 'Refresh prices'))),
        if (failure == FoodFailure.itemUnavailable ||
            failure == FoodFailure.optionsInvalid)
          OutlinedButton(
              onPressed: _cart.clear,
              child: Text(
                  _tx('Очистить корзину', 'Себетті тазалау', 'Clear cart'))),
      ]);
    }
    final quote = state.data!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Row(_tx('Блюда', 'Тауарлар', 'Items'), formatTenge(quote.subtotalMinor)),
      _Row(
          _tx('Доставка', 'Жеткізу', 'Delivery'),
          quote.deliveryFeeMinor == 0
              ? _tx('Бесплатно', 'Тегін', 'Free')
              : formatTenge(quote.deliveryFeeMinor)),
      const SizedBox(height: 4),
      _Row(_tx('Итого', 'Барлығы', 'Total'), formatTenge(quote.totalMinor),
          bold: true),
      if (belowMin)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
              'Минимальная сумма заказа — ${formatTenge(restaurant.minOrderMinor)}. '
              'Добавьте ещё блюд.',
              style: TextStyle(color: theme.colorScheme.error)),
        ),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: belowMin
            ? null
            : () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) =>
                    CheckoutScreen(services: widget.services, quote: quote))),
        child: Text(
            '${_tx('Оформить заказ', 'Тапсырысты рәсімдеу', 'Checkout')} · ${formatTenge(quote.totalMinor)}'),
      ),
    ]);
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.bold = false});

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = bold
        ? Theme.of(context).textTheme.titleLarge
        : Theme.of(context).textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(child: Text(label, style: style)),
        Text(value, style: style)
      ]),
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({required this.line, required this.cart});

  final CartLine line;
  final CartController cart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Row(children: [
          EmojiTile(emoji: line.emoji, tone: line.tone, size: 56, radius: 14),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(line.name, style: theme.textTheme.titleMedium),
              if (line.optionsText.isNotEmpty)
                Text(line.optionsText,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 2),
              Text(
                  line.weighed
                      ? '${formatQuantity(line.unit, line.quantity)} · ${formatTenge(line.totalMinor)}'
                      : formatTenge(line.totalMinor),
                  style: theme.textTheme.titleSmall),
              if (line.substitution != 'NONE')
                Text(
                    line.substitution == 'ANY_SIMILAR'
                        ? 'Замена: на похожий'
                        : 'Замена: на выбранные (${line.substituteDishIds.length})',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.primary)),
            ]),
          ),
          IconButton(
            tooltip:
                line.quantity <= line.step ? 'Удалить ${line.name}' : 'Меньше',
            onPressed: () => cart.setQuantity(line, line.quantity - line.step),
            icon: Icon(line.quantity <= line.step
                ? Icons.delete_outline_rounded
                : Icons.remove_circle_outline_rounded),
          ),
          if (!line.weighed)
            SizedBox(
                width: 24,
                child: Text('${line.quantity}', textAlign: TextAlign.center)),
          IconButton(
            tooltip: 'Больше',
            onPressed: line.quantity + line.step <= line.maxQuantity
                ? () => cart.setQuantity(line, line.quantity + line.step)
                : null,
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
        ]),
      ),
    );
  }
}
