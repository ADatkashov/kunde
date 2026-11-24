import 'package:flutter/material.dart';

import '../../food/data/cart_controller.dart';
import 'package:kunde_models/food_models.dart';
import '../../food/presentation/food_widgets.dart';
import '../data/groceries_api.dart';
import '../data/groceries_models.dart';
import '../data/groceries_services.dart';
import 'groceries_strings.dart';

/// Material icon for a server category icon name; unknown names fall back to a generic category icon.
IconData groceryIcon(String name) => switch (name) {
      'eco' => Icons.eco_outlined,
      'water_drop' => Icons.water_drop_outlined,
      'set_meal' => Icons.set_meal_outlined,
      'phishing' => Icons.phishing_outlined,
      'bakery_dining' => Icons.bakery_dining_outlined,
      'local_drink' => Icons.local_drink_outlined,
      'rice_bowl' => Icons.rice_bowl_outlined,
      'cookie' => Icons.cookie_outlined,
      'ac_unit' => Icons.ac_unit,
      'lunch_dining' => Icons.lunch_dining_outlined,
      'cleaning_services' => Icons.cleaning_services_outlined,
      'child_care' => Icons.child_care_outlined,
      _ => Icons.category_outlined,
    };

/// Adds [product] to the shared cart (pieces, or grams for weighed goods). Asks before replacing a cart that holds
/// another store's products. Returns true when the product is in the cart afterwards.
Future<bool> addProductToCart(
  BuildContext context,
  GroceriesServices services,
  GroceryProduct product, {
  int? quantity,
  List<String> optionIds = const [],
  String optionsText = '',
  int optionsDeltaMinor = 0,
}) async {
  final s = GStr.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final store = await services.storeFor(product.storeId);
    if (!context.mounted) return false;
    if (services.cart.conflictsWith(store.id)) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(s.cartConflictTitle),
          content: Text(s.cartConflictBody),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(s.cancel)),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(s.replaceCart)),
          ],
        ),
      );
      if (replace != true) return false;
    }
    services.cartSync.attach();
    services.cart.add(
      store,
      CartLine(
        dishId: product.id,
        name: product.name,
        emoji: product.emoji,
        tone: product.tone,
        optionIds: optionIds,
        optionsText: optionsText,
        unitPriceMinor: product.priceMinor + optionsDeltaMinor,
        quantity: quantity ?? product.defaultQuantity,
        unit: product.unit,
        maxQuantity: product.maxQuantity < 1 ? 1 : product.maxQuantity,
      ),
    );
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(s.added), duration: const Duration(seconds: 2)));
    return true;
  } on GroceriesException catch (error) {
    messenger
        .showSnackBar(SnackBar(content: Text(error.messageFor(s.language))));
    return false;
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(GStr(s.language).retry)));
    return false;
  }
}

/// The cart line of a plain (no options) product, if any.
CartLine? plainLineOf(CartController cart, String productId) => cart.lines
    .where((l) => l.dishId == productId && l.optionIds.isEmpty)
    .firstOrNull;

class PriceText extends StatelessWidget {
  const PriceText(this.product, {this.large = false, super.key});

  final GroceryProduct product;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final old = product.compareAtPriceMinor;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 6,
      children: [
        Text(
          unitPriceLabel(product.unit, product.priceMinor),
          style: (large
                  ? theme.textTheme.headlineSmall
                  : theme.textTheme.titleMedium)
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (old != null)
          Text(
            formatTenge(old),
            style: theme.textTheme.bodySmall?.copyWith(
                decoration: TextDecoration.lineThrough,
                color: theme.colorScheme.onSurfaceVariant),
          ),
      ],
    );
  }
}

/// A product row of the catalog: photo, name, price, favorite heart and the add / quantity control.
class ProductRow extends StatelessWidget {
  const ProductRow({
    required this.product,
    required this.services,
    required this.onOpen,
    super.key,
  });

  final GroceryProduct product;
  final GroceriesServices services;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = GStr.of(context);
    final sellable = product.inStock && product.storeOpen;
    return Semantics(
      container: true,
      label:
          '${product.name}, ${unitPriceLabel(product.unit, product.priceMinor)}'
          '${sellable ? '' : ', ${product.inStock ? s.storeClosed : s.outOfStock}'}',
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            Opacity(
              opacity: sellable ? 1 : .5,
              child: Stack(children: [
                EmojiTile(
                    emoji: product.emoji,
                    tone: product.tone,
                    size: 84,
                    radius: 18,
                    imageUrl: product.imageUrl),
                if (product.discountPercent != null)
                  Positioned(
                    left: 0,
                    top: 0,
                    child: _Badge('-${product.discountPercent}%',
                        theme.colorScheme.error, theme.colorScheme.onError),
                  )
                else if (product.isNew)
                  Positioned(
                    left: 0,
                    top: 0,
                    child: _Badge(s.newBadge, theme.colorScheme.primary,
                        theme.colorScheme.onPrimary),
                  ),
              ]),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (product.brand != null) product.brand!,
                      product.storeName,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  if (product.ratingAvg != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                          '★ ${product.ratingAvg!.toStringAsFixed(1).replaceAll('.', ',')} (${product.ratingCount})',
                          style: theme.textTheme.bodySmall),
                    ),
                  const SizedBox(height: 6),
                  PriceText(product),
                  if (!sellable)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                          product.inStock ? s.storeClosed : s.outOfStock,
                          style: theme.textTheme.labelMedium
                              ?.copyWith(color: theme.colorScheme.error)),
                    ),
                ],
              ),
            ),
            Column(children: [
              FavoriteButton(services: services, productId: product.id),
              const SizedBox(height: 4),
              if (sellable)
                AddControl(
                    product: product, services: services, onOpen: onOpen),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.background, this.foreground);

  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
            color: background,
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                bottomRight: Radius.circular(10))),
        child: Text(text,
            style: TextStyle(
                color: foreground, fontSize: 11, fontWeight: FontWeight.w800)),
      );
}

/// Heart toggle backed by the server favorites. A failure restores the heart and says why.
class FavoriteButton extends StatelessWidget {
  const FavoriteButton(
      {required this.services, required this.productId, super.key});

  final GroceriesServices services;
  final String productId;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Set<String>>(
        valueListenable: services.favorites,
        builder: (context, ids, _) {
          final s = GStr.of(context);
          final on = ids.contains(productId);
          return IconButton(
            tooltip: s.favorites,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: Icon(on ? Icons.favorite : Icons.favorite_border,
                color: on ? Theme.of(context).colorScheme.error : null),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                await services.toggleFavorite(productId);
              } on GroceriesException catch (error) {
                messenger.showSnackBar(
                    SnackBar(content: Text(error.messageFor(s.language))));
              }
            },
          );
        },
      );
}

/// "+" button that becomes a − / quantity / + stepper once the product is in the cart.
class AddControl extends StatelessWidget {
  const AddControl(
      {required this.product,
      required this.services,
      required this.onOpen,
      this.horizontal = false,
      super.key});

  final GroceryProduct product;
  final GroceriesServices services;
  final VoidCallback onOpen;

  /// Lay the quantity stepper out in a row (shelf cards) instead of a column (list rows).
  final bool horizontal;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: services.cart,
        builder: (context, _) {
          final s = GStr.of(context);
          final scheme = Theme.of(context).colorScheme;
          final line = plainLineOf(services.cart, product.id);
          if (line == null) {
            return IconButton.filled(
              tooltip: s.add,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: () {
                if (product.hasRequiredOptions) {
                  onOpen();
                } else {
                  addProductToCart(context, services, product);
                }
              },
              icon: const Icon(Icons.add),
            );
          }
          return Container(
            decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(24)),
            child: _flex(horizontal, [
              IconButton(
                tooltip: '+',
                onPressed: line.quantity >= line.maxQuantity
                    ? null
                    : () => services.cart
                        .setQuantity(line, line.quantity + line.step),
                icon: const Icon(Icons.add),
              ),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(formatQuantity(line.unit, line.quantity),
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                ),
              ),
              IconButton(
                tooltip: '−',
                onPressed: () =>
                    services.cart.setQuantity(line, line.quantity - line.step),
                icon: const Icon(Icons.remove),
              ),
            ]),
          );
        },
      );

  static Widget _flex(bool horizontal, List<Widget> children) => horizontal
      ? Row(
          mainAxisSize: MainAxisSize.min, children: children.reversed.toList())
      : Column(mainAxisSize: MainAxisSize.min, children: children);
}

/// Loading skeleton of the product list.
class ProductListSkeleton extends StatelessWidget {
  const ProductListSkeleton({this.rows = 6, super.key});

  final int rows;

  @override
  Widget build(BuildContext context) => Column(children: [
        for (var i = 0; i < rows; i++)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(children: [
              SkeletonBox(height: 84, width: 84, radius: 18),
              SizedBox(width: 14),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    SkeletonBox(height: 16),
                    SizedBox(height: 8),
                    SkeletonBox(height: 12, width: 120),
                    SizedBox(height: 10),
                    SkeletonBox(height: 18, width: 90),
                  ])),
            ]),
          ),
      ]);
}

/// Error / empty body with a retry action.
class GroceryMessage extends StatelessWidget {
  const GroceryMessage({
    required this.icon,
    required this.title,
    this.body,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            if (body != null) ...[
              const SizedBox(height: 6),
              Text(body!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium),
            ],
            if (actionLabel != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(
                  onPressed: onAction, child: Text(actionLabel!)),
            ],
          ]),
        ),
      );
}
