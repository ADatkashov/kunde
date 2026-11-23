import 'package:flutter/material.dart';

import '../../beauty/beauty_strings.dart';
import '../../beauty/presentation/beauty_home_screen.dart';
import '../booking_services.dart';
import 'booking_strings.dart';
import 'cleaning_flow_screen.dart';
import 'services_home_screen.dart';
import 'venue_list_screen.dart';

/// Beauty → Barbershops (existing venue → service → master → slot flow).
class BarbershopsEntry extends StatelessWidget {
  const BarbershopsEntry({required this.services, super.key});

  final BookingServices services;

  @override
  Widget build(BuildContext context) {
    final s = bkL10n(context);
    return ServiceEntryCard(
      emoji: '✂️',
      tone: 'blue',
      title: s.bkBarbers,
      subtitle: s.bkBarbersSub,
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => VenueListScreen(services: services))),
    );
  }
}

/// «Красота и уход»: opens the Beauty & Care product (salons, masters, booking).
class BeautyCareEntry extends StatelessWidget {
  const BeautyCareEntry({required this.services, super.key});

  final BookingServices services;

  @override
  Widget build(BuildContext context) {
    final s = bkL10n(context);
    return ServiceEntryCard(
      emoji: '💜',
      tone: 'purple',
      title: s.bHomeTitle,
      subtitle: s.bHomeSubtitle,
      onTap: () => Navigator.of(context).push(beautyShellRouteFor(services)),
    );
  }
}

/// Home services → Cleaning (cleaning type → address → area → price → date/time → request).
class CleaningEntry extends StatelessWidget {
  const CleaningEntry({required this.services, super.key});

  final BookingServices services;

  @override
  Widget build(BuildContext context) {
    final s = bkL10n(context);
    return ServiceEntryCard(
      emoji: '🧹',
      tone: 'green',
      title: s.bkCleaning,
      subtitle: s.bkCleaningSub,
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => CleaningFlowScreen(services: services))),
    );
  }
}

/// «Красота» category page. Only barbershops are live; the rest of the target structure is announced as text.
class BeautyCategoryScreen extends StatelessWidget {
  const BeautyCategoryScreen({required this.services, super.key});

  final BookingServices services;

  @override
  Widget build(BuildContext context) {
    final s = bkL10n(context);
    return _CategoryPage(
      title: s.bkBeautyTitle,
      subtitle: s.bkBeautySubtitle,
      entries: [BarbershopsEntry(services: services)],
      soon: s.bkBeautySoon,
    );
  }
}

/// «Дом и быт» category page. Cleaning is the first live service.
class HomeServicesCategoryScreen extends StatelessWidget {
  const HomeServicesCategoryScreen({required this.services, super.key});

  final BookingServices services;

  @override
  Widget build(BuildContext context) {
    final s = bkL10n(context);
    return _CategoryPage(
      title: s.bkHomeTitle,
      subtitle: s.bkHomeSubtitle,
      entries: [CleaningEntry(services: services)],
      soon: s.bkHomeSoon,
    );
  }
}

class _CategoryPage extends StatelessWidget {
  const _CategoryPage(
      {required this.title,
      required this.subtitle,
      required this.entries,
      required this.soon});

  final String title;
  final String subtitle;
  final List<Widget> entries;
  final String soon;

  @override
  Widget build(BuildContext context) {
    final s = bkL10n(context);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Text(subtitle, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            for (final entry in entries) ...[entry, const SizedBox(height: 12)],
            const SizedBox(height: 4),
            Text(soon,
                style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
            const SizedBox(height: 16),
            Text(s.bkDemoNote,
                style: theme.textTheme.bodySmall?.copyWith(color: muted)),
          ]),
        ),
      ),
    );
  }
}
