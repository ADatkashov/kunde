import 'package:flutter/material.dart';
import 'package:kunde_ui/ride_strings.dart';

import '../data/flowers_models.dart';
import '../data/flowers_services.dart';
import 'flowers_cart_screen.dart';
import 'flowers_widgets.dart';

/// One flowers shop with its products grouped by category. Adding to the cart arrives with ordering (ADR-026 step 3).
class FlowersShopScreen extends StatefulWidget {
  const FlowersShopScreen(
      {required this.services, required this.shopId, super.key});

  final FlowersServices services;
  final String shopId;

  @override
  State<FlowersShopScreen> createState() => _FlowersShopScreenState();
}

class _FlowersShopScreenState extends State<FlowersShopScreen> {
  late Future<FlowersShopDetail> _detail = _load();

  Future<FlowersShopDetail> _load() async =>
      FlowersShopDetail.fromJson(await widget.services.api
              .flowersJson('shops/${Uri.encodeComponent(widget.shopId)}')
          as Map<String, dynamic>);

  Future<void> _add(FlowersShop shop, FlowersProduct p, RideStrings s) async {
    final cart = widget.services.cart;
    if (cart.conflictsWith(shop.id)) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(s.t('Начать новую корзину?',
              'Жаңа себет бастау керек пе?', 'Start a new cart?')),
          content: Text(s.t(
              'В корзине товары другого магазина. Очистить её?',
              'Себетте басқа дүкен тауарлары бар. Тазалайсыз ба?',
              'Your cart has another shop. Clear it?')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(s.t('Нет', 'Жоқ', 'No'))),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(s.t('Да', 'Иә', 'Yes'))),
          ],
        ),
      );
      if (replace != true) return;
      cart.clear();
    }
    cart.add(
        shopId: shop.id,
        shopName: shop.name,
        deliveryFeeMinor: shop.deliveryFeeMinor,
        productId: p.id,
        name: p.name,
        emoji: p.emoji,
        unitPriceMinor: p.priceMinor);
  }

  Widget _control(FlowersShop shop, FlowersProduct p, RideStrings s) {
    if (!p.available) return const SizedBox.shrink();
    final cart = widget.services.cart;
    final line = cart.lines.where((l) => l.productId == p.id).firstOrNull;
    if (line == null || cart.shopId != shop.id) {
      return IconButton.filled(
        key: ValueKey('add-${p.id}'),
        tooltip: s.t('В корзину', 'Себетке', 'Add to cart'),
        onPressed: () => _add(shop, p, s),
        icon: const Icon(Icons.add_rounded),
      );
    }
    return FlowersStepper(
        quantity: line.quantity, onChanged: (q) => cart.setQuantity(p.id, q));
  }

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    return Scaffold(
      appBar: AppBar(),
      bottomNavigationBar: ListenableBuilder(
        listenable: widget.services.cart,
        builder: (context, _) {
          final cart = widget.services.cart;
          if (cart.isEmpty) return const SizedBox.shrink();
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton(
                key: const ValueKey('cart-bar'),
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    shape: const StadiumBorder()),
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) =>
                            FlowersCartScreen(services: widget.services))),
                child: Text(
                    '${s.t('Корзина', 'Себет', 'Cart')} · ${cart.itemCount} · ${formatKzt(cart.subtotalMinor)}'),
              ),
            ),
          );
        },
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListenableBuilder(
            listenable: widget.services.cart,
            builder: (context, _) => FutureBuilder<FlowersShopDetail>(
              future: _detail,
              builder: (context, state) {
                if (state.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state.hasError) {
                  return Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(s.error),
                      TextButton(
                          onPressed: () => setState(() => _detail = _load()),
                          child: Text(s.retry)),
                    ]),
                  );
                }
                final detail = state.data!;
                final theme = Theme.of(context);
                final byCategory = <String, List<FlowersProduct>>{};
                for (final p in detail.products) {
                  byCategory.putIfAbsent(p.categoryCode, () => []).add(p);
                }
                return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: [
                      Text(detail.shop.name,
                          style: theme.textTheme.headlineSmall),
                      if (detail.shop.description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(detail.shop.description,
                            style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant)),
                      ],
                      const SizedBox(height: 10),
                      Wrap(spacing: 8, runSpacing: 6, children: [
                        FlowersPill(
                            '${detail.shop.etaMinMinutes}–${detail.shop.etaMaxMinutes} ${s.t('мин', 'мин', 'min')}',
                            icon: Icons.schedule_rounded),
                        FlowersPill(
                            detail.shop.deliveryFeeMinor == 0
                                ? s.t('Доставка бесплатно', 'Жеткізу тегін',
                                    'Free delivery')
                                : '${s.t('Доставка', 'Жеткізу', 'Delivery')} ${formatKzt(detail.shop.deliveryFeeMinor)}',
                            icon: Icons.local_shipping_outlined),
                        if (!detail.shop.open)
                          FlowersPill(s.t('Закрыто', 'Жабық', 'Closed')),
                      ]),
                      for (final entry in byCategory.entries) ...[
                        const SizedBox(height: 20),
                        Text(entry.key, style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        for (final p in entry.value)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: FlowersProductRow(
                              product: p,
                              trailing: _control(detail.shop, p, s),
                            ),
                          ),
                      ],
                      const SizedBox(height: 12),
                      Text(
                          s.t(
                              'Оформление заказа появится в следующем обновлении.',
                              'Тапсырыс беру келесі жаңартуда қосылады.',
                              'Ordering is coming in the next update.'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ]);
              },
            ),
          ),
        ),
      ),
    );
  }
}
