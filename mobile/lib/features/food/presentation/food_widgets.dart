import 'package:flutter/material.dart';

import '../data/food_models.dart';
import '../food_services.dart';
import 'cart_screen.dart';
import '../../../shared/theme/kunde_art.dart';

/// Rounded tile for dishes and restaurants. Shows [imageUrl] when the catalog has a photo (HTTPS only), otherwise
/// a tone gradient with a large emoji, so a missing or failing image never breaks the layout.
class EmojiTile extends StatelessWidget {
  const EmojiTile(
      {required this.emoji,
      required this.tone,
      this.size = 64,
      this.radius = 16,
      this.imageUrl,
      this.plain = false,
      super.key});

  final String emoji;
  final String tone;
  final double size;
  final double radius;
  final String? imageUrl;
  final bool plain;

  @override
  Widget build(BuildContext context) {
    final colors = toneColors(tone);
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: plain
          ? null
          : BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.85),
                  colors.background
                ],
              ),
              borderRadius: BorderRadius.circular(radius),
            ),
      child: illustrationForEmoji(emoji) != null
          ? KundeIllustration(illustrationForEmoji(emoji)!, size: size * .8)
          : Text(emoji, style: TextStyle(fontSize: size * 0.5)),
    );
    final url = imageUrl;
    return ExcludeSemantics(
      child: url != null && url.startsWith('https://')
          ? ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: Image.network(url,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => fallback,
                  loadingBuilder: (context, child, progress) =>
                      progress == null ? child : fallback),
            )
          : fallback,
    );
  }
}

/// Grey shimmer-free placeholder blocks shown while lists load (skeleton loading).
class SkeletonBox extends StatelessWidget {
  const SkeletonBox(
      {this.height = 16, this.width, this.radius = 12, super.key});

  final double height;
  final double? width;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(radius),
        ),
      );
}

/// Skeleton cards for restaurant / store lists.
class RestaurantListSkeleton extends StatelessWidget {
  const RestaurantListSkeleton({this.count = 4, super.key});

  final int count;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Загрузка',
        child: ListView.separated(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          itemCount: count,
          separatorBuilder: (_, __) => const SizedBox(height: 14),
          itemBuilder: (_, __) => const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(height: 140, radius: 20),
              SizedBox(height: 10),
              SkeletonBox(height: 18, width: 180),
              SizedBox(height: 8),
              SkeletonBox(height: 14, width: 120),
            ],
          ),
        ),
      );
}

class DemoBadge extends StatelessWidget {
  const DemoBadge({super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF0CC),
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Text('ДЕМО',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Color(0xFF7A4B00))),
      );
}

class RestaurantCard extends StatelessWidget {
  const RestaurantCard(
      {required this.restaurant, required this.onTap, super.key});

  final Restaurant restaurant;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fee = restaurant.deliveryFeeMinor == 0
        ? 'Доставка бесплатно'
        : 'Доставка ${formatTenge(restaurant.deliveryFeeMinor)}';
    return Semantics(
      button: true,
      label:
          '${restaurant.name}, ${restaurant.cuisine}, ${restaurant.open ? restaurant.eta : 'закрыто'}',
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        child: InkWell(
          onTap: onTap,
          child: Opacity(
            opacity: restaurant.open ? 1 : 0.55,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                height: 140,
                width: double.infinity,
                alignment: Alignment.center,
                child: Stack(
                    fit: StackFit.expand,
                    alignment: Alignment.center,
                    children: [
                      MerchantArtwork(restaurant: restaurant, height: 140),
                      if (!restaurant.open)
                        Positioned(
                          right: 12,
                          top: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                                color: Colors.black87,
                                borderRadius: BorderRadius.circular(999)),
                            child: const Text('Закрыто',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 12)),
                          ),
                        ),
                      if (restaurant.synthetic)
                        const Positioned(left: 12, top: 12, child: DemoBadge()),
                    ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(restaurant.name, style: theme.textTheme.titleLarge),
                      const SizedBox(height: 2),
                      Text(restaurant.cuisine,
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 8),
                      Wrap(spacing: 14, runSpacing: 4, children: [
                        _Meta(Icons.schedule_rounded, restaurant.eta),
                        _Meta(Icons.delivery_dining_rounded, fee),
                      ]),
                    ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 4),
      Flexible(child: Text(text, style: TextStyle(fontSize: 13, color: color))),
    ]);
  }
}

/// Bottom bar with the cart total; hidden while the cart is empty.
class FoodCartBar extends StatelessWidget {
  const FoodCartBar({required this.services, super.key});

  final FoodServices services;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: services.cart,
        builder: (context, _) {
          final cart = services.cart;
          if (cart.isEmpty) return const SizedBox.shrink();
          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton(
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    padding: const EdgeInsets.symmetric(horizontal: 20)),
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => CartScreen(services: services))),
                child: Row(children: [
                  const Icon(Icons.shopping_bag_outlined),
                  const SizedBox(width: 10),
                  Text(
                      '${cart.restaurant?.vertical == 'FLOWERS_GIFTS' ? switch (Localizations.localeOf(context).languageCode) {
                          'kk' => 'Себет',
                          'en' => 'Cart',
                          _ => 'Корзина'
                        } : 'Корзина'} · ${cart.itemCount}'),
                  const Spacer(),
                  Text(formatTenge(cart.previewSubtotalMinor),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          );
        },
      );
}

/// Loading / error / retry body shared by the Food screens.
class FoodStateMessage extends StatelessWidget {
  const FoodStateMessage(
      {required this.icon,
      required this.title,
      this.body,
      this.actionLabel,
      this.onAction,
      super.key});

  final IconData icon;
  final String title;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 56, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(title,
              textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
          if (body != null) ...[
            const SizedBox(height: 8),
            Text(body!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
          if (onAction != null) ...[
            const SizedBox(height: 20),
            FilledButton(
                onPressed: onAction, child: Text(actionLabel ?? 'Повторить')),
          ],
        ]),
      ),
    );
  }
}

String formatOrderDate(DateTime time) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(time.day)}.${two(time.month)} ${two(time.hour)}:${two(time.minute)}';
}

/// Shared stage hierarchy for cart and checkout; server pricing is unchanged.
class OrderProgressHeader extends StatelessWidget {
  const OrderProgressHeader(
      {required this.checkout, this.flowers = false, super.key});
  final bool checkout;
  final bool flowers;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: colors.primaryContainer,
          borderRadius: BorderRadius.circular(20)),
      child: Row(children: [
        Icon(
            checkout
                ? Icons.local_shipping_outlined
                : Icons.shopping_bag_outlined,
            color: colors.primary),
        const SizedBox(width: 10),
        Expanded(
            child: Text(
                flowers
                    ? switch (Localizations.localeOf(context).languageCode) {
                        'kk' => checkout
                            ? '2 / 2 · Рәсімдеу'
                            : '1 / 2 · Тапсырысыңыз',
                        'en' =>
                          checkout ? '2 / 2 · Checkout' : '1 / 2 · Your order',
                        _ =>
                          checkout ? '2 / 2 · Оформление' : '1 / 2 · Ваш заказ',
                      }
                    : checkout
                        ? '2 / 2 · Оформление'
                        : '1 / 2 · Ваш заказ',
                style: TextStyle(
                    color: colors.onPrimaryContainer,
                    fontWeight: FontWeight.w800))),
        Icon(
            checkout ? Icons.check_circle_rounded : Icons.arrow_forward_rounded,
            color: colors.primary,
            size: 20),
      ]),
    );
  }
}

class FoodCollectionHeader extends StatelessWidget {
  const FoodCollectionHeader({required this.grocery, super.key});
  final bool grocery;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
        child: Row(children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(grocery ? 'Всё для вашего дня' : 'Что-нибудь вкусное?',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800, letterSpacing: -.5)),
                const SizedBox(height: 5),
                Text(
                    grocery
                        ? 'Магазины и свежие продукты рядом'
                        : 'Любимые блюда с доставкой',
                    style: Theme.of(context).textTheme.bodySmall),
              ])),
          const SizedBox(width: 12),
          KundeIllustration(grocery ? 'grocery' : 'food', size: 68),
        ]),
      );
}

/// Catalog photographs are used only when supplied by the merchant API.
/// An offline, missing or broken image always falls back to a licensed illustration.
class MerchantArtwork extends StatelessWidget {
  const MerchantArtwork(
      {required this.restaurant, this.height = 140, super.key});
  final Restaurant restaurant;
  final double height;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      height: height,
      width: double.infinity,
      color: toneColors(restaurant.tone).background,
      alignment: Alignment.center,
      child: EmojiTile(
          emoji: restaurant.emoji,
          tone: restaurant.tone,
          size: height * .85,
          plain: true,
          radius: 0),
    );
    final url = restaurant.imageUrl;
    if (url == null || !url.startsWith('https://')) return fallback;
    return ExcludeSemantics(
        child: Image.network(
      url,
      height: height,
      width: double.infinity,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => fallback,
      loadingBuilder: (_, child, progress) =>
          progress == null ? child : fallback,
    ));
  }
}
