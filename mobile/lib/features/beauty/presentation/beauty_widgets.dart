import 'package:flutter/material.dart';

import '../../../core/localization/kunde_localizations.dart';
import '../beauty_strings.dart';
import '../beauty_theme.dart';
import '../data/beauty_models.dart';

/// Material icon for a category icon code sent by the server.
IconData beautyIcon(String code) => switch (code) {
      'storefront' => Icons.storefront_outlined,
      'content_cut' => Icons.content_cut,
      'back_hand' => Icons.back_hand_outlined,
      'face_retouching_natural' => Icons.face_retouching_natural,
      'self_improvement' => Icons.self_improvement,
      'spa' => Icons.spa_outlined,
      'brush' => Icons.brush_outlined,
      'visibility' => Icons.visibility_outlined,
      'palette' => Icons.palette_outlined,
      'auto_fix_high' => Icons.auto_fix_high,
      'favorite' => Icons.favorite_border,
      _ => Icons.spa_outlined,
    };

/// Large call-to-action with the Beauty gradient.
class BeautyPrimaryButton extends StatelessWidget {
  const BeautyPrimaryButton({
    required this.label,
    required this.onPressed,
    this.loading = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return Opacity(
      opacity: onPressed == null && !loading ? 0.45 : 1,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          gradient: BeautyColors.cta,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: Color(0x336C20F5),
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: enabled ? onPressed : null,
            child: Center(
              child: loading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tile of the 3×3 category grid.
class BeautyCategoryTile extends StatelessWidget {
  const BeautyCategoryTile({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: BeautyColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: BeautyColors.line),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 30, color: BeautyColors.primary),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: BeautyColors.text,
                ),
              ),
            ],
          ),
        ),
      );
}

/// Star, rating and the number of reviews. Shows nothing numeric until there is at least one review.
class BeautyRating extends StatelessWidget {
  const BeautyRating({
    required this.rating,
    required this.reviewCount,
    this.large = false,
    super.key,
  });

  final double? rating;
  final int reviewCount;
  final bool large;

  @override
  Widget build(BuildContext context) {
    if (rating == null || reviewCount == 0) return const SizedBox.shrink();
    final size = large ? 15.0 : 13.0;
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, size: size + 3, color: BeautyColors.rating),
          const SizedBox(width: 3),
          Text(
            rating!.toStringAsFixed(1),
            style: TextStyle(
                fontSize: size,
                fontWeight: FontWeight.w800,
                color: BeautyColors.rating),
          ),
          const SizedBox(width: 4),
          Text(
            '($reviewCount)',
            style: TextStyle(fontSize: size, color: BeautyColors.muted),
          ),
        ],
      ),
    );
  }
}

/// Price chip, «от 5 000 ₸».
class BeautyPrice extends StatelessWidget {
  const BeautyPrice({
    required this.minor,
    this.from = true,
    this.large = false,
    super.key,
  });

  final int minor;
  final bool from;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    final text = s.bFromPrice(minor, from: from);
    if (large) {
      return Text(
        text,
        style: const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w800,
          color: BeautyColors.text,
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: BeautyColors.lavender,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: BeautyColors.primary,
        ),
      ),
    );
  }
}

/// Time chip of the slot grid.
class BeautyTimeSlot extends StatelessWidget {
  const BeautyTimeSlot({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? BeautyColors.primary : BeautyColors.lavender,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : BeautyColors.text,
            ),
          ),
        ),
      );
}

/// Pill with the status of a booking.
class BeautyBookingStatus extends StatelessWidget {
  const BeautyBookingStatus(
      {required this.status, required this.label, super.key});

  final String status;
  final String label;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (status) {
      'COMPLETED' => (const Color(0xFFDDF5E8), BeautyColors.success),
      'CANCELLED' || 'REJECTED' => (
          const Color(0xFFFDE4E1),
          BeautyColors.error
        ),
      'PENDING' => (const Color(0xFFFFF1D6), const Color(0xFFB7791F)),
      _ => (BeautyColors.lavender, BeautyColors.primary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700, color: foreground),
      ),
    );
  }
}

class BeautySectionHeader extends StatelessWidget {
  const BeautySectionHeader(this.title, {this.trailing, super.key});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 20, 0, 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: BeautyColors.text,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      );
}

class BeautyFilterChip extends StatelessWidget {
  const BeautyFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? BeautyColors.primary : BeautyColors.lavender,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : BeautyColors.primary,
            ),
          ),
        ),
      );
}

/// A gradient placeholder with an icon until a licensed salon photo is available.
class BeautyPhoto extends StatelessWidget {
  const BeautyPhoto({
    required this.imageUrl,
    required this.icon,
    this.size = 84,
    this.radius = 16,
    super.key,
  });

  final String? imageUrl;
  final IconData icon;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(
          width: size,
          height: size,
          child: imageUrl != null
              ? Image.network(
                  imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _placeholder(),
                )
              : _placeholder(),
        ),
      );

  Widget _placeholder() => DecoratedBox(
        decoration: const BoxDecoration(gradient: BeautyColors.hero),
        child: Center(
          child: Icon(icon, size: size * 0.4, color: Colors.white70),
        ),
      );
}

/// Row card of a salon in the catalog.
class BeautySalonCard extends StatelessWidget {
  const BeautySalonCard({
    required this.salon,
    required this.favorite,
    required this.onTap,
    required this.onFavorite,
    super.key,
  });

  final BeautySalon salon;
  final bool favorite;
  final VoidCallback onTap;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BeautyPhoto(
              imageUrl: salon.imageUrl,
              icon: Icons.spa_outlined,
              size: 88,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    salon.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: BeautyColors.text,
                    ),
                  ),
                  const SizedBox(height: 3),
                  BeautyRating(
                      rating: salon.rating, reviewCount: salon.reviewCount),
                  const SizedBox(height: 3),
                  Text(
                    [
                      salon.addressText,
                      if (salon.distanceMeters != null)
                        s.bKm(salon.distanceMeters!),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12.5, color: BeautyColors.muted),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (salon.fromPriceMinor != null)
                        BeautyPrice(minor: salon.fromPriceMinor!),
                      if (salon.discountPercent != null)
                        Text(
                          '−${salon.discountPercent}%',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: BeautyColors.error,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: s.bFavorites,
              onPressed: onFavorite,
              icon: Icon(
                favorite ? Icons.favorite : Icons.favorite_border,
                color: favorite ? BeautyColors.primary : BeautyColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Row of a service inside a salon.
class BeautyServiceCard extends StatelessWidget {
  const BeautyServiceCard({
    required this.service,
    required this.onTap,
    super.key,
  });

  final BeautyService service;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: BeautyColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: BeautyColors.line),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    service.name,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: BeautyColors.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    s.bDuration(service.durationMinutes),
                    style: const TextStyle(
                        fontSize: 13, color: BeautyColors.muted),
                  ),
                ],
              ),
            ),
            BeautyPrice(minor: service.priceMinor, from: service.priceFrom),
            const Icon(Icons.chevron_right, color: BeautyColors.muted),
          ],
        ),
      ),
    );
  }
}

/// Four-step indicator Услуга → Время → Оплата → Готово (steps before [current] are done).
class BeautyStepper extends StatelessWidget {
  const BeautyStepper({required this.current, super.key});

  final int current;

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    final labels = [s.bStepService, s.bStepTime, s.bStepPayment, s.bStepDone];
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          Expanded(
            child: Column(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i <= current
                        ? BeautyColors.primary
                        : BeautyColors.lavender,
                  ),
                  child: Icon(
                    i < current ? Icons.check : Icons.circle,
                    size: i < current ? 18 : 8,
                    color: i <= current ? Colors.white : BeautyColors.muted,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color:
                        i <= current ? BeautyColors.text : BeautyColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Month calendar. Only days in [first]..[last] can be chosen.
class BeautyCalendar extends StatelessWidget {
  const BeautyCalendar({
    required this.month,
    required this.selected,
    required this.first,
    required this.last,
    required this.onSelect,
    required this.onMonthChanged,
    super.key,
  });

  /// Any day of the shown month.
  final DateTime month;
  final DateTime? selected;
  final DateTime first;
  final DateTime last;
  final ValueChanged<DateTime> onSelect;
  final ValueChanged<DateTime> onMonthChanged;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    final monthStart = DateTime(month.year, month.month);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final offset = monthStart.weekday - 1;
    final canPrev = monthStart.isAfter(DateTime(first.year, first.month));
    final canNext = DateTime(month.year, month.month + 1)
        .isBefore(DateTime(last.year, last.month + 1));
    final cells = <Widget>[
      for (final w in s.bWeekdays)
        Center(
          child: Text(w,
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: BeautyColors.muted)),
        ),
      for (var i = 0; i < offset; i++) const SizedBox.shrink(),
      for (var day = 1; day <= daysInMonth; day++)
        _DayCell(
          day: DateTime(month.year, month.month, day),
          selected: selected != null &&
              _day(selected!) == DateTime(month.year, month.month, day),
          enabled:
              !DateTime(month.year, month.month, day).isBefore(_day(first)) &&
                  !DateTime(month.year, month.month, day).isAfter(_day(last)),
          onTap: onSelect,
        ),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: BeautyColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: canPrev
                    ? () =>
                        onMonthChanged(DateTime(month.year, month.month - 1))
                    : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  s.bMonthYear(month),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                onPressed: canNext
                    ? () =>
                        onMonthChanged(DateTime(month.year, month.month + 1))
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.1,
            children: cells,
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final DateTime day;
  final bool selected;
  final bool enabled;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) => Center(
        child: InkResponse(
          onTap: enabled ? () => onTap(day) : null,
          child: Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? BeautyColors.primary : Colors.transparent,
            ),
            child: Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected
                    ? Colors.white
                    : enabled
                        ? BeautyColors.text
                        : BeautyColors.muted.withValues(alpha: 0.4),
              ),
            ),
          ),
        ),
      );
}
