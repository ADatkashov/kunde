import 'package:flutter/material.dart';

import 'booking_strings.dart';

import '../../food/data/food_models.dart' show toneColors;
import '../../food/presentation/food_widgets.dart';
import '../booking_services.dart';
import '../data/booking_api.dart';
import '../data/booking_models.dart';
import 'booking_flow_screen.dart';

/// Barbershop page: description, services (tap to book) and masters.
class VenueScreen extends StatefulWidget {
  const VenueScreen({required this.services, required this.venue, super.key});

  final BookingServices services;
  final BookingVenue venue;

  @override
  State<VenueScreen> createState() => _VenueScreenState();
}

class _VenueScreenState extends State<VenueScreen> {
  late Future<VenueDetail> _detail = widget.services.api.venue(widget.venue.id);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final venue = widget.venue;
    final s = bkL10n(context);
    return Scaffold(
      appBar: AppBar(title: Text(venue.name)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: FutureBuilder<VenueDetail>(
            future: _detail,
            builder: (context, state) {
              if (state.connectionState != ConnectionState.done) {
                return const RestaurantListSkeleton(count: 3);
              }
              if (state.hasError) {
                final error = state.error;
                return FoodStateMessage(
                    icon: Icons.cloud_off_outlined,
                    title: s.bkVenueLoadError,
                    body: error is BookingException
                        ? s.bkError(error.failure)
                        : null,
                    onAction: () => setState(() {
                          _detail = widget.services.api.venue(venue.id);
                        }));
              }
              final detail = state.data!;
              return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    Container(
                      height: 120,
                      decoration: BoxDecoration(
                          color: toneColors(venue.tone).background,
                          borderRadius: BorderRadius.circular(20)),
                      alignment: Alignment.center,
                      child: ExcludeSemantics(
                          child: Text(venue.emoji,
                              style: const TextStyle(fontSize: 64))),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                          child: Text(venue.name,
                              style: theme.textTheme.headlineSmall)),
                      if (venue.synthetic) const DemoBadge(),
                    ]),
                    const SizedBox(height: 4),
                    Row(children: [
                      const Icon(Icons.location_on_outlined, size: 18),
                      const SizedBox(width: 4),
                      Expanded(child: Text(venue.addressText)),
                    ]),
                    const SizedBox(height: 4),
                    Text(venue.description,
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 20),
                    Text(s.bkServices, style: theme.textTheme.titleLarge),
                    const SizedBox(height: 8),
                    for (final service in detail.services)
                      _ServiceTile(
                        service: service,
                        enabled: venue.open &&
                            service.available &&
                            detail.mastersFor(service.id).isNotEmpty,
                        onBook: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                                builder: (_) => BookingFlowScreen(
                                    services: widget.services,
                                    detail: detail,
                                    service: service))),
                      ),
                    const SizedBox(height: 20),
                    Text(s.bkMasters, style: theme.textTheme.titleLarge),
                    const SizedBox(height: 8),
                    for (final m in detail.masters)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: EmojiTile(
                            emoji: m.emoji, tone: m.tone, size: 48, radius: 14),
                        title: Text(m.name),
                        subtitle: Text(m.bio),
                      ),
                  ]);
            },
          ),
        ),
      ),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile(
      {required this.service, required this.enabled, required this.onBook});

  final BookableService service;
  final bool enabled;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = bkL10n(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.bkCatalogName(service.name),
                style: theme.textTheme.titleMedium),
            if (service.description.isNotEmpty)
              Text(service.description,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 2),
            Text(
                '${formatDuration(service.durationMinutes)} · ${formatTenge(service.priceMinor)}',
                style: theme.textTheme.titleSmall),
          ]),
        ),
        const SizedBox(width: 12),
        FilledButton.tonal(
          onPressed: enabled ? onBook : null,
          child: Text(enabled ? s.bkBookAction : s.bkUnavailable),
        ),
      ]),
    );
  }
}
