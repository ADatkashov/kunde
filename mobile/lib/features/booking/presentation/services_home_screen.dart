import 'package:flutter/material.dart';

import '../../food/presentation/food_widgets.dart';
import '../../home/presentation/home_strings.dart';
import '../booking_services.dart';
import 'booking_strings.dart';
import 'category_screens.dart';

/// «Все сервисы»: the common catalog of KUNDE services grouped by user-facing category (not a business category).
/// Barbershops live under «Красота», cleaning under «Дом и быт»; both use the same booking mechanism inside.
class ServicesHomeScreen extends StatelessWidget {
  const ServicesHomeScreen({
    required this.services,
    this.homeServicesEnabled = false,
    super.key,
  });

  final BookingServices services;
  final bool homeServicesEnabled;

  @override
  Widget build(BuildContext context) {
    final s = bkL10n(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.allServicesTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Text(s.bkAllServicesIntro, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            Text(s.catBeauty, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            BarbershopsEntry(services: services),
            if (homeServicesEnabled) ...[
              const SizedBox(height: 20),
              Text(s.catHome, style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              CleaningEntry(services: services),
            ],
            const SizedBox(height: 20),
            Text(s.bkDemoNote,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }
}

/// Large tappable card of one live service inside a category.
class ServiceEntryCard extends StatelessWidget {
  const ServiceEntryCard(
      {required this.emoji,
      required this.tone,
      required this.title,
      required this.subtitle,
      required this.onTap,
      super.key});

  final String emoji;
  final String tone;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: '$title. $subtitle',
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: theme.colorScheme.outlineVariant)),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              ExcludeSemantics(
                  child: EmojiTile(
                      emoji: emoji, tone: tone, size: 64, radius: 18)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleLarge),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ]),
              ),
              const Icon(Icons.chevron_right_rounded),
            ]),
          ),
        ),
      ),
    );
  }
}
