import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/localization/kunde_localizations.dart';
import '../../booking/booking_services.dart';
import '../beauty_strings.dart';
import '../beauty_theme.dart';
import '../data/beauty_models.dart';
import 'beauty_master_screen.dart';
import 'beauty_support.dart';
import 'beauty_widgets.dart';

/// Service card («Окрашивание волос»): photo area, rating, tags, price, duration, description and «Записаться».
class BeautyServiceScreen extends StatelessWidget {
  const BeautyServiceScreen({
    required this.services,
    required this.favorites,
    required this.serviceId,
    super.key,
  });

  final BookingServices services;
  final BeautyFavorites favorites;
  final String serviceId;

  @override
  Widget build(BuildContext context) => Scaffold(
        extendBodyBehindAppBar: true,
        body: BeautyAsync<BeautyServiceDetail>(
          load: () => services.beauty.service(serviceId),
          builder: (context, detail) => _ServiceBody(
            services: services,
            favorites: favorites,
            detail: detail,
          ),
        ),
      );
}

class _ServiceBody extends StatelessWidget {
  const _ServiceBody({
    required this.services,
    required this.favorites,
    required this.detail,
  });

  final BookingServices services;
  final BeautyFavorites favorites;
  final BeautyServiceDetail detail;

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    final service = detail.service;
    final salon = detail.salon;
    final experienced =
        detail.masters.any((m) => (m.experienceYears ?? 0) >= 3);
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              SizedBox(
                height: 300,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (detail.gallery.isNotEmpty)
                      Image.network(detail.gallery.first,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const _HeroFallback())
                    else
                      const _HeroFallback(),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Row(
                          children: [
                            _RoundButton(
                              icon: Icons.arrow_back_ios_new,
                              onTap: () => Navigator.of(context).maybePop(),
                            ),
                            const Spacer(),
                            ListenableBuilder(
                              listenable: favorites,
                              builder: (context, _) => _RoundButton(
                                icon: favorites.contains(salon.id)
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                onTap: () => toggleFavorite(
                                    context, favorites, salon.id),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _RoundButton(
                              icon: Icons.ios_share,
                              onTap: () => SharePlus.instance.share(
                                ShareParams(
                                  text:
                                      '${service.name} · ${salon.name} · ${s.bFromPrice(service.priceMinor, from: service.priceFrom)}',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (detail.gallery.length > 1)
                      Positioned(
                        right: 16,
                        bottom: 40,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text('1/${detail.gallery.length}',
                              style: const TextStyle(color: Colors.white)),
                        ),
                      ),
                  ],
                ),
              ),
              Transform.translate(
                offset: const Offset(0, -24),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
                  decoration: const BoxDecoration(
                    color: BeautyColors.background,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(28)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(service.name,
                          style: const TextStyle(
                              fontSize: 26, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          BeautyRating(
                              rating: salon.rating,
                              reviewCount: salon.reviewCount,
                              large: true),
                          if (salon.reviewCount > 0) ...[
                            const SizedBox(width: 8),
                            Text(s.bReviewsCount(salon.reviewCount),
                                style:
                                    const TextStyle(color: BeautyColors.muted)),
                          ],
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          for (final tag in service.tags) _Tag(tag),
                        ],
                      ),
                      const SizedBox(height: 14),
                      BeautyPrice(
                          minor: service.priceMinor,
                          from: service.priceFrom,
                          large: true),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: BeautyColors.surface,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.schedule,
                                size: 18, color: BeautyColors.primary),
                            const SizedBox(width: 6),
                            Text(s.bDuration(service.durationMinutes),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                      if (service.description.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text(service.description,
                            style: const TextStyle(fontSize: 15, height: 1.4)),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          if (experienced)
                            Expanded(
                              child: _InfoTile(
                                  icon: Icons.workspace_premium_outlined,
                                  label: s.bExperienced),
                            ),
                          if (experienced && salon.verified)
                            const SizedBox(width: 10),
                          if (salon.verified)
                            Expanded(
                              child: _InfoTile(
                                  icon: Icons.verified_outlined,
                                  label: s.bVerifiedSalon),
                            ),
                        ],
                      ),
                      if (detail.includes.isNotEmpty) ...[
                        BeautySectionHeader(s.bIncluded),
                        for (final item in detail.includes)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle,
                                    size: 18, color: BeautyColors.primary),
                                const SizedBox(width: 8),
                                Expanded(child: Text(item)),
                              ],
                            ),
                          ),
                      ],
                      if (detail.preparation.isNotEmpty) ...[
                        BeautySectionHeader(s.bPreparation),
                        Text(detail.preparation),
                      ],
                      BeautySectionHeader(s.bSalon),
                      Text(salon.name,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text(salon.addressText,
                          style: const TextStyle(color: BeautyColors.muted)),
                      if (detail.cancellationPolicy.isNotEmpty) ...[
                        BeautySectionHeader(s.bCancelPolicy),
                        Text(detail.cancellationPolicy),
                      ],
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: BeautyPrimaryButton(
              label: s.bBook,
              onPressed: detail.masters.isEmpty
                  ? null
                  : () => Navigator.of(context).push(beautyRoute(
                        BeautyMasterScreen(
                            services: services,
                            favorites: favorites,
                            detail: detail),
                      )),
            ),
          ),
        ),
      ],
    );
  }
}

class _HeroFallback extends StatelessWidget {
  const _HeroFallback();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(gradient: BeautyColors.hero),
        child: Center(
          child: Icon(Icons.spa, size: 96, color: Color(0x55FFFFFF)),
        ),
      );
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(icon, size: 20, color: BeautyColors.text),
          ),
        ),
      );
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: BeautyColors.lavender,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: BeautyColors.primary)),
      );
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: BeautyColors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, color: BeautyColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}
