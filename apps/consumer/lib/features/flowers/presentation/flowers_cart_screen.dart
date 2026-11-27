import 'package:flutter/material.dart';
import 'package:kunde_ui/ride_strings.dart';

import '../data/flowers_services.dart';
import 'flowers_checkout_screen.dart';
import 'flowers_widgets.dart';

/// Cart of one flowers shop: quantity steppers and the order summary (preview; the server prices the order at checkout).
class FlowersCartScreen extends StatelessWidget {
  const FlowersCartScreen({required this.services, super.key});

  final FlowersServices services;

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    final cart = services.cart;
    return ListenableBuilder(
      listenable: cart,
      builder: (context, _) {
        final theme = Theme.of(context);
        final fee = cart.deliveryFeeMinor;
        return Scaffold(
          appBar: AppBar(
            centerTitle: true,
            title: Text(
                '${s.t('Корзина', 'Себет', 'Cart')} (${cart.itemCount})',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            actions: [
              if (!cart.isEmpty)
                IconButton(
                  tooltip: s.t('Очистить', 'Тазалау', 'Clear'),
                  onPressed: cart.clear,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
            ],
          ),
          body: cart.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                        s.t('Корзина пуста', 'Себет бос', 'Your cart is empty'),
                        style: theme.textTheme.titleMedium),
                  ),
                )
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child:
                        ListView(padding: const EdgeInsets.all(16), children: [
                      Text(cart.shopName ?? '',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 12),
                      for (final line in cart.lines)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(children: [
                            FlowersPhoto(
                                emoji: line.emoji, imageUrl: null, size: 64),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(line.name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800)),
                                    Text(formatKzt(line.totalMinor),
                                        style: TextStyle(
                                            color: theme.colorScheme.primary,
                                            fontWeight: FontWeight.w800)),
                                  ]),
                            ),
                            FlowersStepper(
                              quantity: line.quantity,
                              onChanged: (q) =>
                                  cart.setQuantity(line.productId, q),
                            ),
                          ]),
                        ),
                      const Divider(height: 28),
                      _row(s.t('Товары', 'Тауарлар', 'Items'),
                          formatKzt(cart.subtotalMinor)),
                      _row(
                          s.t('Доставка', 'Жеткізу', 'Delivery'),
                          fee == 0
                              ? s.t('Бесплатно', 'Тегін', 'Free')
                              : formatKzt(fee)),
                      const Divider(height: 28),
                      Row(children: [
                        Expanded(
                            child: Text(s.t('Итого', 'Барлығы', 'Total'),
                                style: theme.textTheme.titleLarge)),
                        Text(formatKzt(cart.subtotalMinor + fee),
                            style: theme.textTheme.headlineSmall),
                      ]),
                    ]),
                  ),
                ),
          bottomNavigationBar: cart.isEmpty
              ? null
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: FilledButton(
                      key: const ValueKey('checkout'),
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                          shape: const StadiumBorder()),
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                              builder: (_) =>
                                  FlowersCheckoutScreen(services: services))),
                      child: Text(
                          s.t('Оформить заказ', 'Тапсырыс беру', 'Checkout')),
                    ),
                  ),
                ),
        );
      },
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [Expanded(child: Text(label)), Text(value)]),
      );
}
