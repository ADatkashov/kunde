import 'package:flutter/material.dart';

import '../../../core/localization/kunde_localizations.dart';
import '../../booking/booking_services.dart';
import '../beauty_strings.dart';
import '../beauty_theme.dart';
import '../data/beauty_models.dart';
import 'beauty_service_screen.dart';
import 'beauty_support.dart';
import 'beauty_widgets.dart';

/// Salon page: about, services (open a service card), masters, reviews and cancellation terms.
class BeautySalonScreen extends StatelessWidget {
  const BeautySalonScreen({
    required this.services,
    required this.favorites,
    required this.salon,
    super.key,
  });

  final BookingServices services;
  final BeautyFavorites favorites;
  final BeautySalon salon;

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(salon.name),
        actions: [
          ListenableBuilder(
            listenable: favorites,
            builder: (context, _) => IconButton(
              tooltip: s.bFavorites,
              onPressed: () => toggleFavorite(context, favorites, salon.id),
              icon: Icon(
                favorites.contains(salon.id)
                    ? Icons.favorite
                    : Icons.favorite_border,
                color:
                    favorites.contains(salon.id) ? BeautyColors.primary : null,
              ),
            ),
          ),
        ],
      ),
      body: BeautyAsync<BeautySalonDetail>(
        load: () => services.beauty.salon(salon.id),
        builder: (context, detail) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            Row(
              children: [
                BeautyPhoto(
                    imageUrl: salon.imageUrl,
                    icon: Icons.spa_outlined,
                    size: 96,
                    radius: 20),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      BeautyRating(
                          rating: salon.rating,
                          reviewCount: salon.reviewCount,
                          large: true),
                      const SizedBox(height: 4),
                      Text(salon.addressText,
                          style: const TextStyle(color: BeautyColors.muted)),
                      if (salon.verified) ...[
                        const SizedBox(height: 6),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.verified,
                                size: 16, color: BeautyColors.primary),
                            const SizedBox(width: 4),
                            Text(s.bVerifiedSalon,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: BeautyColors.primary)),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (detail.description.isNotEmpty) ...[
              BeautySectionHeader(s.bAbout),
              Text(detail.description),
            ],
            BeautySectionHeader(s.bServicesTitle),
            for (final service in detail.services)
              BeautyServiceCard(
                service: service,
                onTap: () => Navigator.of(context).push(beautyRoute(
                  BeautyServiceScreen(
                    services: services,
                    favorites: favorites,
                    serviceId: service.id,
                  ),
                )),
              ),
            if (detail.masters.isNotEmpty) ...[
              BeautySectionHeader(s.bMastersTitle),
              for (final master in detail.masters) _MasterRow(master: master),
            ],
            BeautySectionHeader(s.bReviewsTitle),
            if (detail.reviews.isEmpty)
              Text(s.bNoReviews,
                  style: const TextStyle(color: BeautyColors.muted))
            else
              for (final review in detail.reviews) _ReviewRow(review: review),
            if (detail.cancellationPolicy.isNotEmpty) ...[
              BeautySectionHeader(s.bCancelPolicy),
              Text(detail.cancellationPolicy),
            ],
          ],
        ),
      ),
    );
  }
}

class _MasterRow extends StatelessWidget {
  const _MasterRow({required this.master});

  final BeautyMaster master;

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const CircleAvatar(
        backgroundColor: BeautyColors.lavender,
        child: Icon(Icons.person, color: BeautyColors.primary),
      ),
      title: Text(master.name,
          style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text([
        if (master.specialty.isNotEmpty) master.specialty,
        if (master.experienceYears != null)
          s.bExperienceYears(master.experienceYears!),
      ].join(' · ')),
      trailing:
          BeautyRating(rating: master.rating, reviewCount: master.reviewCount),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.review});

  final BeautyReview review;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: BeautyColors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (var i = 0; i < 5; i++)
                  Icon(
                    i < review.rating
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    size: 18,
                    color: BeautyColors.rating,
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    review.authorName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12.5, color: BeautyColors.muted),
                  ),
                ),
              ],
            ),
            if (review.comment.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(review.comment),
            ],
          ],
        ),
      );
}
