import 'package:flutter/material.dart';
import 'package:kunde_design/kunde_design.dart';

import '../data/leisure_api.dart';
import '../data/leisure_models.dart';
import 'leisure_strings.dart';

/// Icon of a Leisure category (the 16 codes of the backend); unknown codes fall back to a ticket.
IconData leisureIcon(String code) => switch (code) {
      'CINEMA' => Icons.movie_rounded,
      'BOWLING' => Icons.sports_score_rounded,
      'KARAOKE' => Icons.mic_external_on_rounded,
      'QUEST' => Icons.vpn_key_rounded,
      'KIDS_CENTER' => Icons.child_care_rounded,
      'TRAMPOLINE' => Icons.sports_gymnastics_rounded,
      'GAMING_VR' => Icons.view_in_ar_rounded,
      'BILLIARDS' => Icons.sports_bar_rounded,
      'CONCERT' => Icons.music_note_rounded,
      'THEATER' => Icons.theater_comedy_rounded,
      'EXHIBITION' => Icons.museum_rounded,
      'MASTERCLASS' => Icons.palette_rounded,
      'EXCURSION' => Icons.directions_walk_rounded,
      'ACTIVE' => Icons.hiking_rounded,
      'FAMILY' => Icons.family_restroom_rounded,
      _ => Icons.confirmation_number_rounded,
    };

/// Honest placeholder palette per category: DEV data has no licensed photos, so a venue without a photo gets an illustrated gradient.
List<Color> leisureGradient(String code) => switch (code) {
      'CINEMA' => const [Color(0xFF271D62), Color(0xFF7055F5)],
      'BOWLING' => const [Color(0xFF1B3A6B), Color(0xFF4A7BE0)],
      'KARAOKE' => const [Color(0xFF5A1B6B), Color(0xFFD05AE0)],
      'QUEST' => const [Color(0xFF2C2540), Color(0xFF8A6BD6)],
      'KIDS_CENTER' || 'FAMILY' => const [Color(0xFFB8541E), Color(0xFFF2A65C)],
      'TRAMPOLINE' => const [Color(0xFF0E6B62), Color(0xFF45C2A8)],
      'CONCERT' || 'THEATER' => const [Color(0xFF6B1B3A), Color(0xFFE05A86)],
      'EXHIBITION' || 'MASTERCLASS' => const [
          Color(0xFF4A3A1B),
          Color(0xFFD6A94A)
        ],
      'EXCURSION' || 'ACTIVE' => const [Color(0xFF1B5A3A), Color(0xFF5CC27A)],
      _ => const [Color(0xFF3A3F7A), Color(0xFF7C85E8)],
    };

class LeisureArt extends StatelessWidget {
  const LeisureArt({required this.category, this.iconSize = 44, super.key});

  final String category;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final colors = leisureGradient(category);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors),
      ),
      child: Stack(fit: StackFit.expand, children: [
        Positioned(
          right: -iconSize * .25,
          bottom: -iconSize * .3,
          child: Icon(leisureIcon(category),
              size: iconSize * 2.6, color: Colors.white.withValues(alpha: .13)),
        ),
        Center(
            child: Icon(leisureIcon(category),
                size: iconSize, color: Colors.white.withValues(alpha: .92))),
      ]),
    );
  }
}

/// Network photo when the venue has one, the category illustration otherwise (also on a load error).
class EventPhoto extends StatelessWidget {
  const EventPhoto(
      {required this.url,
      required this.category,
      this.iconSize = 44,
      super.key});

  final String? url;
  final String category;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final art = LeisureArt(category: category, iconSize: iconSize);
    if (url == null || url!.isEmpty) return ExcludeSemantics(child: art);
    return Image.network(
      url!,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => art,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : art,
    );
  }
}

class SkeletonBox extends StatefulWidget {
  const SkeletonBox(
      {this.height = 16, this.width, this.radius = 12, super.key});

  final double height;
  final double? width;
  final double radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            color: base.withValues(alpha: .45 + _c.value * .4),
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        ),
      ),
    );
  }
}

class EventTileSkeleton extends StatelessWidget {
  const EventTileSkeleton({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.only(bottom: 14),
        child: Row(children: [
          SkeletonBox(height: 104, width: 112, radius: 18),
          SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                SkeletonBox(height: 18, width: 160),
                SizedBox(height: 10),
                SkeletonBox(height: 14, width: 110),
                SizedBox(height: 10),
                SkeletonBox(height: 14, width: 80),
              ])),
        ]),
      );
}

/// Loading / error-with-retry / empty states shared by the Leisure screens.
class LeisureStateView extends StatelessWidget {
  const LeisureStateView.loading({super.key})
      : failure = null,
        onRetry = null,
        title = null,
        body = null,
        icon = null;

  const LeisureStateView.error(
      {required LeisureFailure this.failure, required this.onRetry, super.key})
      : title = null,
        body = null,
        icon = null;

  const LeisureStateView.empty(
      {required String this.title, this.body, this.icon, super.key})
      : failure = null,
        onRetry = null;

  final LeisureFailure? failure;
  final VoidCallback? onRetry;
  final String? title;
  final String? body;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final s = lzL10n(context);
    final theme = Theme.of(context);
    if (failure == null && title == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Column(children: [
          EventTileSkeleton(),
          EventTileSkeleton(),
          EventTileSkeleton(),
        ]),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle),
            child: Icon(
                failure != null
                    ? Icons.cloud_off_rounded
                    : (icon ?? Icons.search_off_rounded),
                size: 34,
                color: theme.colorScheme.onPrimaryContainer),
          ),
          const SizedBox(height: 16),
          Text(failure != null ? s.lzError(failure!) : title!,
              textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
          if (body != null) ...[
            const SizedBox(height: 8),
            Text(body!,
                textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
          ],
          if (failure != null && onRetry != null) ...[
            const SizedBox(height: 18),
            FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(s.lzRetry)),
          ],
        ]),
      ),
    );
  }
}

class LeisureErrorBanner extends StatelessWidget {
  const LeisureErrorBanner(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: scheme.errorContainer,
            borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Icon(Icons.error_outline_rounded, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
              child:
                  Text(text, style: TextStyle(color: scheme.onErrorContainer))),
        ]),
      ),
    );
  }
}

class RatingBadge extends StatelessWidget {
  const RatingBadge({required this.rating, required this.count, super.key});

  final double rating;
  final int count;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Semantics(
      label: '${rating.toStringAsFixed(1)} ($count)',
      child: ExcludeSemantics(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.star_rounded, size: 16, color: KundePalette.gold),
          const SizedBox(width: 3),
          Text(rating.toStringAsFixed(1),
              style: style?.copyWith(fontWeight: FontWeight.w800)),
          Text(' ($count)', style: style),
        ]),
      ),
    );
  }
}

class MiniChip extends StatelessWidget {
  const MiniChip(this.text, {this.filled = false, super.key});

  final String text;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: filled
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest.withValues(alpha: .6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(fontWeight: FontWeight.w700)),
    );
  }
}

/// Catalogue row: photo, title, rating (only real), district, badges and the price from the server.
class EventTile extends StatelessWidget {
  const EventTile({
    required this.card,
    required this.onTap,
    this.favorite,
    this.onFavorite,
    super.key,
  });

  final EventCard card;
  final VoidCallback onTap;
  final bool? favorite;
  final VoidCallback? onFavorite;

  @override
  Widget build(BuildContext context) {
    final s = lzL10n(context);
    final theme = Theme.of(context);
    final soldOut = card.nextSessionFree <= 0;
    return Semantics(
      button: true,
      label:
          '${card.title}, ${card.venueName}, ${s.lzFromPrice(formatTenge(card.minPriceMinor))}',
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Material(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(22),
          elevation: 1.5,
          shadowColor: KundePalette.shadow,
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                      width: 108,
                      height: 108,
                      child: EventPhoto(
                          url: card.photoUrl,
                          category: card.categoryCode,
                          iconSize: 38)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(card.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w800)),
                              ),
                              if (onFavorite != null)
                                InkResponse(
                                  onTap: onFavorite,
                                  radius: 22,
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Semantics(
                                      button: true,
                                      label: s.lzFavorite,
                                      toggled: favorite == true,
                                      child: Icon(
                                          favorite == true
                                              ? Icons.favorite_rounded
                                              : Icons.favorite_border_rounded,
                                          size: 22,
                                          color: favorite == true
                                              ? const Color(0xFFE0405E)
                                              : theme.colorScheme
                                                  .onSurfaceVariant),
                                    ),
                                  ),
                                ),
                            ]),
                        const SizedBox(height: 4),
                        if (card.rating != null)
                          RatingBadge(
                              rating: card.rating!, count: card.reviewCount),
                        Text(
                            [
                              if (card.district.isNotEmpty) card.district,
                              if (card.distanceKm != null)
                                '${card.distanceKm} km',
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall),
                        const SizedBox(height: 6),
                        Wrap(spacing: 6, runSpacing: 4, children: [
                          if (card.minAge > 0)
                            MiniChip(s.lzAgeLimit(card.minAge)),
                          if (card.familyFriendly) MiniChip('👨‍👩‍👧'),
                          MiniChip(
                              soldOut
                                  ? s.lzFree(0)
                                  : s.lzWhen(card.nextSessionAt),
                              filled: !soldOut),
                        ]),
                        const SizedBox(height: 6),
                        Text(s.lzFromPrice(formatTenge(card.minPriceMinor)),
                            style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: theme.colorScheme.primary)),
                      ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Filled purple call-to-action that stays above the system navigation bar and is large enough for a thumb.
class PrimaryBar extends StatelessWidget {
  const PrimaryBar(
      {required this.label,
      required this.onPressed,
      this.busy = false,
      this.top,
      super.key});

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final Widget? top;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      elevation: 10,
      shadowColor: KundePalette.shadow,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (top != null) ...[top!, const SizedBox(height: 10)],
            SizedBox(
              width: double.infinity,
              height: 56,
              child: Semantics(
                identifier: 'leisure-primary',
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18)),
                      textStyle: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w800)),
                  onPressed: busy ? null : onPressed,
                  child: busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5))
                      : FittedBox(fit: BoxFit.scaleDown, child: Text(label)),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Three-step progress of the booking (session, seats, purchase) as in the design reference.
class BookingStepper extends StatelessWidget {
  const BookingStepper(
      {required this.current, required this.labels, super.key});

  final int current;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: labels[current],
      child: Row(children: [
        for (var i = 0; i < labels.length; i++) ...[
          Expanded(
            child: Column(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i <= current
                        ? scheme.primary
                        : scheme.surfaceContainerHighest,
                    border: i == current
                        ? Border.all(color: scheme.primaryContainer, width: 4)
                        : null),
                child: Icon(i < current ? Icons.check_rounded : Icons.circle,
                    size: i < current ? 18 : 8,
                    color: i <= current ? scheme.onPrimary : scheme.outline),
              ),
              const SizedBox(height: 6),
              Text(labels[i],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight:
                          i == current ? FontWeight.w800 : FontWeight.w500,
                      color: i <= current
                          ? scheme.primary
                          : scheme.onSurfaceVariant)),
            ]),
          ),
          if (i < labels.length - 1)
            Expanded(
                child: Padding(
                    padding: const EdgeInsets.only(bottom: 22),
                    child: Divider(
                        thickness: 2,
                        color: i < current
                            ? scheme.primary
                            : scheme.outlineVariant))),
        ],
      ]),
    );
  }
}

String leisureWeekdayShort(BuildContext context, DateTime d) =>
    lzL10n(context).weekday(d);
