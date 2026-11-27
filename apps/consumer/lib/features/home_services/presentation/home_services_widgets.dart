import 'package:flutter/material.dart';
import 'package:kunde_design/kunde_design.dart';
import 'package:kunde_ui/ride_strings.dart';

/// Icon and localized label of a Home Services category code (`marketplace.home_service_categories`).
(IconData, String) homeCategoryMeta(RideStrings s, String code) =>
    switch (code) {
      'CLEANING' => (
          Icons.cleaning_services_rounded,
          s.t('Уборка', 'Үй жинау', 'Cleaning'),
        ),
      'PLUMBING' => (
          Icons.plumbing_rounded,
          s.t('Сантехника', 'Сантехника', 'Plumbing'),
        ),
      'ELECTRICAL' => (
          Icons.electrical_services_rounded,
          s.t('Электрика', 'Электр жұмыстары', 'Electrical'),
        ),
      'REPAIR_INSTALLATION' => (
          Icons.handyman_rounded,
          s.t('Ремонт', 'Жөндеу', 'Repair'),
        ),
      'FURNITURE' => (
          Icons.chair_rounded,
          s.t('Сборка мебели', 'Жиһаз құрастыру', 'Furniture'),
        ),
      'APPLIANCES' => (
          Icons.home_repair_service_rounded,
          s.t('Техника', 'Техника', 'Appliances'),
        ),
      'HANDYMAN' => (
          Icons.construction_rounded,
          s.t('Мастер на час', 'Бір сағатқа шебер', 'Handyman'),
        ),
      'FINISHING' => (
          Icons.format_paint_rounded,
          s.t('Покраска', 'Сырлау', 'Painting'),
        ),
      _ => (Icons.home_repair_service_rounded, s.t('Другое', 'Басқа', 'Other')),
    };

/// Violet hero of the «Дом и быт» screens: back button, title, subtitle and the bundled home photo on the right.
class HomeServicesHero extends StatelessWidget {
  const HomeServicesHero({
    required this.title,
    required this.subtitle,
    super.key,
  });

  final String title;
  final String subtitle;

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
      child: Stack(
        children: [
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 190,
            child: ExcludeSemantics(
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (rect) => const LinearGradient(
                  colors: [Color(0x00FFFFFF), Color(0xFFFFFFFF)],
                  stops: [0, .55],
                ).createShader(rect),
                child: Image.asset(
                  'assets/photos/home-services.jpg',
                  fit: BoxFit.cover,
                  alignment: Alignment.centerRight,
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (canPop)
                    IconButton(
                      tooltip:
                          MaterialLocalizations.of(context).backButtonTooltip,
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    )
                  else
                    const SizedBox(height: 48),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 150, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context)
                              .textTheme
                              .headlineLarge
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// White sheet with rounded top corners that slides over the violet hero.
class HomeServicesSheet extends StatelessWidget {
  const HomeServicesSheet({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: KundePalette.violet,
        child: Material(
          color: Theme.of(context).scaffoldBackgroundColor,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      );
}

/// Rounded tonal tile with a category icon (reference: lilac square with a violet glyph).
class HomeServiceTile extends StatelessWidget {
  const HomeServiceTile(this.icon, {this.size = 64, super.key});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, colors.primaryContainer],
          ),
          borderRadius: BorderRadius.circular(size * .28),
        ),
        child: Icon(icon, size: size * .5, color: colors.primary),
      ),
    );
  }
}

/// Compact tonal capsule: price, home visit, warranty.
class HomeServicePill extends StatelessWidget {
  const HomeServicePill(this.text, {this.icon, this.strong = false, super.key});

  final String text;
  final IconData? icon;

  /// Filled violet capsule for the price.
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fg = strong ? colors.onPrimaryContainer : colors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: strong ? .75 : .45),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: fg),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: strong ? FontWeight.w800 : FontWeight.w700,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Rounded white card with a leading violet icon and a caption: one field of the order form.
class HomeServiceField extends StatelessWidget {
  const HomeServiceField({
    required this.icon,
    required this.label,
    required this.child,
    super.key,
  });

  final IconData icon;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: .6)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: colors.primary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  child,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Four-step tracker of a visit: accepted → on the way → working → done. [step] is 0..3.
class HomeServiceStepper extends StatelessWidget {
  const HomeServiceStepper({
    required this.step,
    required this.labels,
    super.key,
  }) : assert(step >= 0 && step < 4);

  final int step;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Widget dot(int i) {
      final done = i < step;
      final active = i == step;
      return Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: done || active ? colors.primary : colors.surfaceContainerHigh,
          border: active
              ? Border.all(color: colors.primaryContainer, width: 4)
              : null,
        ),
        child: Icon(
          done ? Icons.check_rounded : Icons.circle,
          size: done ? 18 : 8,
          color: done || active ? Colors.white : colors.outline,
        ),
      );
    }

    Widget line(int i) => Expanded(
          child: Container(
            height: 3,
            margin: const EdgeInsets.only(top: 12.5),
            color: i < step ? colors.primary : colors.surfaceContainerHigh,
          ),
        );
    return ExcludeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < 4; i++) ...[
            SizedBox(
              width: 56,
              child: Column(
                children: [
                  dot(i),
                  const SizedBox(height: 6),
                  Text(
                    labels[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: i == step ? FontWeight.w800 : FontWeight.w600,
                      color: i <= step ? colors.onSurface : colors.outline,
                    ),
                  ),
                ],
              ),
            ),
            if (i < 3) line(i),
          ],
        ],
      ),
    );
  }
}
