import 'package:flutter/material.dart';
import 'package:kunde_design/kunde_design.dart';
import 'package:kunde_ui/ride_strings.dart';

import '../data/flowers_models.dart';

String formatKzt(int minor) {
  final tenge = (minor / 100).round().toString();
  final grouped =
      tenge.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ');
  return '$grouped ₸';
}

/// Material icon for a category icon name sent by the server; unknown names fall back to a flower.
IconData flowersCategoryIcon(String name) => switch (name) {
      'inventory_2' => Icons.inventory_2_outlined,
      'spa' => Icons.spa_outlined,
      'card_giftcard' => Icons.card_giftcard_outlined,
      'cake' => Icons.cake_outlined,
      'toys' => Icons.toys_outlined,
      'mail' => Icons.mail_outline_rounded,
      'more_horiz' => Icons.more_horiz_rounded,
      _ => Icons.local_florist_outlined,
    };

/// Violet hero of the Flowers & Gifts screens (same language as the Food and Home Services heroes).
class FlowersHero extends StatelessWidget {
  const FlowersHero(
      {required this.title, required this.subtitle, this.actions, super.key});

  final String title;
  final String subtitle;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [KundePalette.deepViolet, KundePalette.violet],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 24),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (canPop)
                IconButton(
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: Colors.white, size: 20),
                )
              else
                const SizedBox(height: 48),
              const Spacer(),
              ...?actions,
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: Theme.of(context)
                            .textTheme
                            .headlineLarge
                            ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 14, height: 1.3)),
                  ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class FlowersSheet extends StatelessWidget {
  const FlowersSheet({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: KundePalette.violet,
        child: Material(
          color: Theme.of(context).scaffoldBackgroundColor,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      );
}

class FlowersPill extends StatelessWidget {
  const FlowersPill(this.text, {this.icon, super.key});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: .6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 15, color: colors.primary),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: colors.onPrimaryContainer)),
        ),
      ]),
    );
  }
}

/// Square tile: HTTPS photo when the catalogue has one, otherwise a tonal gradient with the emoji.
class FlowersPhoto extends StatelessWidget {
  const FlowersPhoto(
      {required this.emoji, required this.imageUrl, this.size = 72, super.key});

  final String emoji;
  final String? imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, colors.primaryContainer],
        ),
        borderRadius: BorderRadius.circular(size * .24),
      ),
      child: Text(emoji, style: TextStyle(fontSize: size * .5)),
    );
    final url = imageUrl;
    return ExcludeSemantics(
      child: url != null && url.startsWith('https://')
          ? ClipRRect(
              borderRadius: BorderRadius.circular(size * .24),
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

class FlowersShopCard extends StatelessWidget {
  const FlowersShopCard({required this.shop, required this.onTap, super.key});

  final FlowersShop shop;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label:
          '${shop.name}, ${shop.etaMinMinutes}–${shop.etaMaxMinutes} ${s.t('мин', 'мин', 'min')}',
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: .6))),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FlowersPhoto(
                  emoji: shop.emoji, imageUrl: shop.imageUrl, size: 84),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(shop.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        FlowersPill(
                            shop.open
                                ? '${shop.etaMinMinutes}–${shop.etaMaxMinutes} ${s.t('мин', 'мин', 'min')}'
                                : s.t('Закрыто', 'Жабық', 'Closed'),
                            icon: Icons.schedule_rounded),
                        FlowersPill(
                            shop.deliveryFeeMinor == 0
                                ? s.t('Доставка бесплатно', 'Жеткізу тегін',
                                    'Free delivery')
                                : '${s.t('Доставка', 'Жеткізу', 'Delivery')} ${formatKzt(shop.deliveryFeeMinor)}',
                            icon: Icons.local_shipping_outlined),
                      ]),
                    ]),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: theme.colorScheme.outline),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Compact product tile of the «Популярное» carousel.
class FlowersProductCard extends StatelessWidget {
  const FlowersProductCard(
      {required this.product, required this.onTap, super.key});

  final FlowersProduct product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: '${product.name}, ${formatKzt(product.priceMinor)}',
      child: SizedBox(
        width: 132,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FlowersPhoto(
                emoji: product.emoji, imageUrl: product.imageUrl, size: 132),
            const SizedBox(height: 6),
            Text(product.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(formatKzt(product.priceMinor),
                style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w800)),
          ]),
        ),
      ),
    );
  }
}

class FlowersProductRow extends StatelessWidget {
  const FlowersProductRow({required this.product, this.trailing, super.key});

  final FlowersProduct product;

  /// Add-to-cart control on the right (a button or a quantity stepper).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    final theme = Theme.of(context);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      FlowersPhoto(emoji: product.emoji, imageUrl: product.imageUrl, size: 64),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(product.name,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          if (product.description.isNotEmpty)
            Text(product.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13, color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(
              product.available
                  ? formatKzt(product.priceMinor)
                  : s.t('Нет в наличии', 'Қолжетімсіз', 'Unavailable'),
              style: TextStyle(
                  color: product.available
                      ? theme.colorScheme.primary
                      : theme.colorScheme.error,
                  fontWeight: FontWeight.w800)),
        ]),
      ),
      if (trailing != null) trailing!,
    ]);
  }
}

/// Round «− 1 +» quantity control of the product card and the cart.
class FlowersStepper extends StatelessWidget {
  const FlowersStepper(
      {required this.quantity,
      required this.onChanged,
      this.max = 20,
      super.key});

  final int quantity;
  final ValueChanged<int> onChanged;
  final int max;

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton.outlined(
        tooltip: s.t('Меньше', 'Азайту', 'Decrease'),
        visualDensity: VisualDensity.compact,
        onPressed: () => onChanged(quantity - 1),
        icon: const Icon(Icons.remove_rounded),
      ),
      SizedBox(
          width: 32,
          child: Text('$quantity',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium)),
      IconButton.filled(
        tooltip: s.t('Больше', 'Көбейту', 'Increase'),
        visualDensity: VisualDensity.compact,
        onPressed: quantity < max ? () => onChanged(quantity + 1) : null,
        icon: const Icon(Icons.add_rounded),
      ),
    ]);
  }
}
