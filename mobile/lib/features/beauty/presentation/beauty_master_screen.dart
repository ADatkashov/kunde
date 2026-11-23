import 'package:flutter/material.dart';

import '../../../core/localization/kunde_localizations.dart';
import '../../booking/booking_services.dart';
import '../beauty_strings.dart';
import '../beauty_theme.dart';
import '../data/beauty_models.dart';
import 'beauty_datetime_screen.dart';
import 'beauty_support.dart';
import 'beauty_widgets.dart';

/// Choose a master qualified for the service, or any available master.
class BeautyMasterScreen extends StatefulWidget {
  const BeautyMasterScreen({
    required this.services,
    required this.favorites,
    required this.detail,
    super.key,
  });

  final BookingServices services;
  final BeautyFavorites favorites;
  final BeautyServiceDetail detail;

  @override
  State<BeautyMasterScreen> createState() => _BeautyMasterScreenState();
}

class _BeautyMasterScreenState extends State<BeautyMasterScreen> {
  /// Null = any master.
  String? _masterId;

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    final detail = widget.detail;
    final nearest = [
      for (final m in detail.masters)
        if (m.nextSlotAt != null) m.nextSlotAt!
    ]..sort();
    return Scaffold(
      appBar: AppBar(title: Text(s.bPickMaster)),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _MasterCard(
                  selected: _masterId == null,
                  onTap: () => setState(() => _masterId = null),
                  leading: const CircleAvatar(
                    backgroundColor: BeautyColors.lavender,
                    child: Icon(Icons.groups, color: BeautyColors.primary),
                  ),
                  title: s.bAnyMaster,
                  subtitle: nearest.isEmpty
                      ? s.bNoFreeTime
                      : s.bNearest(s.bDayTime(nearest.first)),
                  price: detail.service.priceMinor,
                  priceFrom: detail.service.priceFrom,
                ),
                for (final master in detail.masters)
                  _MasterCard(
                    selected: _masterId == master.id,
                    onTap: () => setState(() => _masterId = master.id),
                    leading: const CircleAvatar(
                      backgroundColor: BeautyColors.lavender,
                      child: Icon(Icons.person, color: BeautyColors.primary),
                    ),
                    title: master.name,
                    subtitle: [
                      if (master.specialty.isNotEmpty) master.specialty,
                      if (master.experienceYears != null)
                        s.bExperienceYears(master.experienceYears!),
                      master.nextSlotAt == null
                          ? s.bNoFreeTime
                          : s.bNearest(s.bDayTime(master.nextSlotAt!)),
                    ].join('\n'),
                    rating: master.rating,
                    reviewCount: master.reviewCount,
                    price: detail.service.priceMinor,
                    priceFrom: detail.service.priceFrom,
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: BeautyPrimaryButton(
                label: s.bContinue,
                onPressed: () {
                  final master = _masterId == null
                      ? null
                      : detail.masters.firstWhere((m) => m.id == _masterId);
                  Navigator.of(context).push(beautyRoute(
                    BeautyDateTimeScreen(
                      services: widget.services,
                      favorites: widget.favorites,
                      detail: detail,
                      master: master,
                    ),
                  ));
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MasterCard extends StatelessWidget {
  const _MasterCard({
    required this.selected,
    required this.onTap,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.price,
    required this.priceFrom,
    this.rating,
    this.reviewCount = 0,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget leading;
  final String title;
  final String subtitle;
  final int price;
  final bool priceFrom;
  final double? rating;
  final int reviewCount;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? BeautyColors.lavender : BeautyColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? BeautyColors.primary : BeautyColors.line,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                    if (rating != null && reviewCount > 0)
                      BeautyRating(rating: rating, reviewCount: reviewCount),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 13, color: BeautyColors.muted)),
                  ],
                ),
              ),
              BeautyPrice(minor: price, from: priceFrom),
            ],
          ),
        ),
      );
}
