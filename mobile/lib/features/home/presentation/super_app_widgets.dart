import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../../core/localization/kunde_localizations.dart';
import 'home_strings.dart';
import '../../../shared/theme/kunde_art.dart';

/// Fixed brand greens used on hero surfaces (AI card, banner). White text on
/// them passes AA in both light and dark themes.
const kundeHeroGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF004A37), Color(0xFF007A50), Color(0xFF00875A)],
);

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

class KundeMark extends StatelessWidget {
  const KundeMark({this.size = 44, super.key});

  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: SizedBox(
            width: size,
            height: size,
            child: const CustomPaint(painter: KundeLogoPainter())),
      );
}

class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF5FBFF), Color(0xFFE5F4FD)],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Stack(
        children: [
          const Positioned(
            right: 0,
            bottom: -18,
            width: 185,
            height: 70,
            child: CustomPaint(painter: AlmatyMountains()),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const KundeMark(size: 42),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'KUNDE',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontSize: 25,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.8,
                        color: const Color(0xFF004A37),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      s.homeTagline,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 10,
                        height: 1.3,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                child: InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    builder: (context) => SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              s.homeLocationLabel,
                              style: theme.textTheme.titleLarge,
                            ),
                            const SizedBox(height: 12),
                            ListTile(
                              leading: const Icon(Icons.location_on_rounded),
                              title: Text(s.homeCity),
                              trailing: const Icon(Icons.check_circle_rounded),
                              onTap: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 14,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 3),
                        Text(s.homeCity, style: theme.textTheme.labelMedium),
                        const Icon(Icons.keyboard_arrow_down_rounded, size: 16),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
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
      elevation: 3,
      shadowColor: const Color(0x180E4933),
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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

/// AI entry. Never simulates a working assistant: the action stays disabled
/// until the app has a real AI capability to open.
class AiEntryCard extends StatelessWidget {
  const AiEntryCard({this.onAsk, super.key});

  final VoidCallback? onAsk;

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: kundeHeroGradient,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          const KundeIllustration('robot', size: 66),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: [
                    Text(
                      s.homeAiTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (onAsk == null) SoonBadge(onDark: true),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  onAsk == null ? s.homeAiUnavailable : s.homeAiSubtitle,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
          ),
          if (onAsk != null) ...[
            const SizedBox(width: 8),
            FilledButton(
              onPressed: onAsk,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF053D36),
                foregroundColor: Colors.white,
              ),
              child: Text(s.homeAiAsk),
            ),
          ],
        ],
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
        // 5 columns from a 360 px screen (328 px content); fewer when the
        // content is narrower or the user enlarges text, so labels never clip.
        final columns = scale > 1.5 || box.maxWidth < 250
            ? 3
            : scale > 1.15 || box.maxWidth < 328
                ? 4
                : 5;
        const gap = 4.0;
        final width = (box.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final c in categories)
              SizedBox(
                width: width,
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
    final highlighted = category.enabled && !category.isAll;
    final muted = !category.enabled && !category.isAll;
    final status = category.isAll
        ? ''
        : ', ${category.enabled ? s.categoryAvailable : s.homeSoon}';
    return Semantics(
      button: true,
      label: '${category.label}$status',
      child: ExcludeSemantics(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: highlighted
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: highlighted
                  ? theme.colorScheme.primary
                  : category.enabled || category.isAll
                      ? theme.colorScheme.outlineVariant
                      : Colors.transparent,
              width: highlighted ? 2 : 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 110),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 1,
                  vertical: 10,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    KundeIllustration(
                        switch (category.icon) {
                          Icons.ramen_dining_rounded => 'food',
                          Icons.shopping_basket_rounded => 'grocery',
                          Icons.local_taxi_rounded => 'rides',
                          Icons.inventory_2_rounded => 'delivery',
                          Icons.home_rounded => 'home',
                          Icons.content_cut_rounded => 'beauty',
                          Icons.favorite_rounded => 'health',
                          Icons.directions_car_rounded => 'auto',
                          Icons.confirmation_number_rounded => 'leisure',
                          _ => 'services',
                        },
                        size: 42),
                    const SizedBox(height: 6),
                    Text(
                      category.label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    if (muted) ...[
                      const SizedBox(height: 4),
                      const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: SoonBadge(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FoodBanner extends StatelessWidget {
  const FoodBanner({this.onOrder, super.key});

  /// Null while the marketplace is not enabled: the action is shown disabled.
  final VoidCallback? onOrder;

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/photos/food.jpg',
              fit: BoxFit.cover,
              alignment: Alignment.centerRight,
              excludeFromSemantics: true,
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF003C2D),
                    const Color(0xFF003C2D).withValues(alpha: .94),
                    const Color(0xFF003C2D).withValues(alpha: .05),
                  ],
                  stops: const [0, .6, 1],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Expanded(
                  flex: 7,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFC4F59E),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          s.bannerBadge,
                          style: const TextStyle(
                            color: Color(0xFF003C2D),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        s.bannerTitle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 25,
                          height: 1.08,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -.6,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        onOrder == null ? s.bannerBody : s.bannerBodyLive,
                        style: const TextStyle(
                          color: Color(0xFFE0EFE8),
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: onOrder,
                        icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                        label: Text(
                          onOrder == null ? s.homeSoon : s.bannerCtaLive,
                        ),
                        iconAlignment: IconAlignment.end,
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF003C2D),
                          disabledBackgroundColor: Colors.white70,
                          disabledForegroundColor: const Color(0xFF003C2D),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          textStyle: const TextStyle(
                            fontFamily: 'KundeSans',
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(flex: 3),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
      shadowColor: const Color(0x180E4933),
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
  const SectionTitle({required this.title, this.trailing, super.key});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Flexible(
          child: Semantics(
            header: true,
            child: Text(title, style: theme.textTheme.titleLarge),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          Icon(Icons.location_on, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 2),
          Text(trailing!, style: theme.textTheme.bodySmall),
        ],
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
