import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:kunde_design/kunde_design.dart';

import '../../../core/localization/kunde_localizations.dart';
import '../../../shared/theme/kunde_art.dart';
import 'home_strings.dart';

/// Fades and lifts its child in once; skipped when animations are disabled.
class FadeIn extends StatelessWidget {
  const FadeIn({required this.child, this.delay = 0, super.key});

  final Widget child;
  final int delay;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 280 + delay),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, lerpDouble(12, 0, t)!),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class HomeHeader extends StatelessWidget {
  const HomeHeader({required this.onNotifications, super.key});

  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Semantics(
              label: 'KUNDE',
              excludeSemantics: true,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  children: [
                    const CustomPaint(
                      size: Size(34, 34),
                      painter: KundeLogoPainter(),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'KUNDE',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1,
                              ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * .39,
          ),
          child: TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              builder: (context) => SafeArea(
                child: ListTile(
                  leading: const Icon(Icons.location_on_outlined),
                  title: Text(s.homeCity),
                  trailing: const Icon(Icons.check_rounded),
                  onTap: () => Navigator.pop(context),
                ),
              ),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              backgroundColor: colors.surface,
              foregroundColor: colors.onSurface,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 18,
                  color: colors.primary,
                ),
                const SizedBox(width: 4),
                Flexible(child: Text(s.homeCity)),
                const Icon(Icons.keyboard_arrow_down_rounded, size: 16),
              ],
            ),
          ),
        ),
        IconButton(
          tooltip: s.homeNotifications,
          onPressed: onNotifications,
          icon: const Icon(Icons.notifications_none_rounded),
        ),
      ],
    );
  }
}

class HomeSearchField extends StatelessWidget {
  const HomeSearchField({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      elevation: 2,
      shadowColor: theme.colorScheme.shadow.withValues(alpha: .18),
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.search_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Semantics(
                    button: true,
                    label: s.homeSearchHint,
                    child: ExcludeSemantics(
                      child: Text(
                        s.homeSearchHint,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AiOrb extends StatelessWidget {
  const AiOrb({this.size = 40, this.branded = false, super.key});

  final double size;
  final bool branded;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * (branded ? .29 : .5)),
            gradient: const LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [Color(0xFF493CEF), Color(0xFFCF7CF5)],
            ),
            boxShadow: const [
              BoxShadow(
                  color: Color(0xA89161FF), blurRadius: 16, spreadRadius: 1),
            ],
          ),
          child: branded
              ? Center(
                  child: CustomPaint(
                    size: Size.square(size * .52),
                    painter: const KundeLogoPainter(),
                  ),
                )
              : Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: size * .58,
                ),
        ),
      );
}

enum HomePromotion { assistant, rewards, membership }

class HomePromoCard extends StatelessWidget {
  const HomePromoCard({
    required this.promotion,
    required this.label,
    required this.onTap,
    super.key,
  });

  final HomePromotion promotion;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (colors, icon, foreground) = switch (promotion) {
      HomePromotion.assistant => (
          const [Color(0xFF3B248F), Color(0xFF7447CB)],
          Icons.auto_awesome_rounded,
          Colors.white,
        ),
      HomePromotion.rewards => (
          const [Color(0xFFE8DBFC), Color(0xFFF6EEFF)],
          Icons.card_giftcard_rounded,
          const Color(0xFF211442),
        ),
      HomePromotion.membership => (
          const [Color(0xFFBB843D), Color(0xFFFFE4A8)],
          Icons.workspace_premium_rounded,
          const Color(0xFF36220D),
        ),
    };
    return Material(
      color: colors.first,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(16),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                if (promotion == HomePromotion.assistant)
                  const AiOrb(size: 27)
                else
                  Icon(icon, color: foreground, size: 24),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(label,
                          style: TextStyle(
                            color: foreground,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          )),
                      Text(KundeLocalizations.of(context).homeSoon,
                          style: TextStyle(
                              color: foreground,
                              fontSize: 10,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SoonBadge extends StatelessWidget {
  const SoonBadge({this.onDark = false, super.key});

  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: onDark ? Colors.white24 : theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        KundeLocalizations.of(context).homeSoon,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: onDark ? Colors.white : theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

class ServiceCategory {
  const ServiceCategory({
    required this.icon,
    required this.label,
    required this.color,
    this.enabled = false,
    this.isAll = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool enabled;
  final bool isAll;
}

class CategoryGrid extends StatelessWidget {
  const CategoryGrid({
    required this.categories,
    required this.onTap,
    super.key,
  });

  final List<ServiceCategory> categories;
  final ValueChanged<ServiceCategory> onTap;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(
      builder: (context, box) {
        final columns = scale > 1.5
            ? 2
            : scale > 1.15 || box.maxWidth < 300
                ? 3
                : 4;
        const gap = 8.0;
        final width = (box.maxWidth - gap * (columns - 1)) / columns;
        final height = 44 + MediaQuery.textScalerOf(context).scale(38);
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final c in categories)
              SizedBox(
                width: width,
                height: height,
                child: CategoryTile(category: c, onTap: () => onTap(c)),
              ),
          ],
        );
      },
    );
  }
}

class CategoryTile extends StatelessWidget {
  const CategoryTile({required this.category, required this.onTap, super.key});

  final ServiceCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final status = category.isAll
        ? ''
        : ', ${category.enabled ? s.categoryAvailable : s.homeSoon}';
    final artwork = switch (category.icon) {
      Icons.ramen_dining_rounded => 'burger',
      Icons.shopping_basket_rounded => 'grocery',
      Icons.home_rounded => 'home',
      Icons.directions_car_rounded => 'auto',
      Icons.confirmation_number_rounded => 'leisure',
      Icons.favorite_rounded => 'health',
      _ => null,
    };
    final iconColor = Color.alphaBlend(
      colors.onSurface.withValues(
        alpha: theme.brightness == Brightness.dark ? .42 : .05,
      ),
      category.color,
    );
    return Semantics(
      button: true,
      onTap: onTap,
      label: '${category.label}$status',
      child: ExcludeSemantics(
        child: Material(
          color: colors.surface,
          elevation: 2,
          shadowColor: colors.shadow.withValues(alpha: .16),
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (artwork != null)
                    KundeIllustration(artwork, size: 36)
                  else
                    SizedBox.square(
                      dimension: 36,
                      child: Icon(category.icon, size: 28, color: iconColor),
                    ),
                  const SizedBox(height: 4),
                  Flexible(
                    child: Text(
                      category.label,
                      textAlign: TextAlign.center,
                      softWrap: category.label.contains(' '),
                      maxLines: category.label.contains(' ') ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontSize: 11,
                        height: 1.18,
                        letterSpacing: 0,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (!category.enabled && !category.isAll)
                    Flexible(
                      child: Text(
                        s.homeSoon,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 9,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FoodBanner extends StatelessWidget {
  const FoodBanner({this.onOrder, this.compact = false, super.key});

  /// Null while the marketplace is not enabled: the action is shown disabled.
  final VoidCallback? onOrder;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    return Material(
      color: const Color(0xFF21193D),
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/photos/food-banner.webp',
              fit: BoxFit.cover,
              alignment: Alignment.center,
              excludeFromSemantics: true,
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xD921193D), Color(0x0021193D)],
                  stops: [0, .64],
                ),
              ),
            ),
          ),
          Semantics(
            button: true,
            enabled: onOrder != null,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onOrder,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 6,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.bannerTitle,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: compact ? 19 : 22,
                                fontWeight: FontWeight.w800,
                                height: 1.12,
                              ),
                            ),
                            const SizedBox(height: 6),
                            if (!compact)
                              Text(s.bannerSubtitle,
                                  style: const TextStyle(color: Colors.white)),
                            const SizedBox(height: 12),
                            if (onOrder == null)
                              const SoonBadge(onDark: true)
                            else
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: KundePalette.gold,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 7,
                                  ),
                                  child: Wrap(
                                    spacing: 6,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        s.bannerCtaLive,
                                        style: const TextStyle(
                                          color: Color(0xFF101426),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const Icon(Icons.arrow_forward_rounded,
                                          size: 16, color: Color(0xFF101426)),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const Spacer(flex: 4),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ServicePhotoCard extends StatelessWidget {
  const ServicePhotoCard({
    required this.label,
    required this.asset,
    required this.onTap,
    super.key,
  });

  final String label;
  final String asset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Ink.image(
                  image: AssetImage(asset), height: 80, fit: BoxFit.cover),
              Padding(
                padding: const EdgeInsets.all(8),
                child:
                    Text(label, style: Theme.of(context).textTheme.labelLarge),
              ),
            ],
          ),
        ),
      );
}

class QuickAction extends StatelessWidget {
  const QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      elevation: 3,
      shadowColor: KundePalette.shadow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge,
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({required this.title, this.action, super.key});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
        ),
        if (action != null)
          Flexible(
              child: Align(
                  alignment: AlignmentDirectional.centerEnd, child: action!)),
      ],
    );
  }
}

class EmptyStateCard extends StatelessWidget {
  const EmptyStateCard({
    required this.icon,
    required this.title,
    required this.body,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(body, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
