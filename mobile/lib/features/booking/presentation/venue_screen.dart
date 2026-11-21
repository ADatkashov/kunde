import 'package:flutter/material.dart';

import 'booking_strings.dart';

import '../../food/data/food_models.dart' show toneColors;
import '../../food/presentation/food_widgets.dart';
import '../../health/health_specialist_screen.dart';
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

  late Future<List<HealthFavorite>> _favorites =
      widget.services.api.healthFavorites(venueId: widget.venue.id);
  final _saving = <(HealthFavoriteKind, String)>{};

  Widget _favoriteButton(HealthFavoriteKind kind, String id) {
    final s = bkL10n(context);
    return FutureBuilder<List<HealthFavorite>>(
      future: _favorites,
      builder: (context, snapshot) {
        final items = snapshot.data;
        if (snapshot.hasError) {
          return IconButton(
            tooltip: s.bkRetry,
            onPressed: () => setState(() {
              _favorites = widget.services.api.healthFavorites(
                venueId: widget.venue.id,
              );
            }),
            icon: const Icon(Icons.refresh),
          );
        }
        final key = (kind, id);
        final saved =
            items?.any((item) => item.kind == kind && item.id == id) ?? false;
        return IconButton(
          tooltip: saved
              ? s.healthText('Убрать из избранного', 'Таңдаулыдан өшіру',
                  'Remove from favorites')
              : s.healthText(
                  'В избранное', 'Таңдаулыға қосу', 'Add to favorites'),
          icon: Icon(saved ? Icons.favorite : Icons.favorite_border),
          onPressed: items == null ||
                  snapshot.connectionState != ConnectionState.done ||
                  _saving.contains(key)
              ? null
              : () async {
                  setState(() => _saving.add(key));
                  try {
                    await widget.services.api
                        .setHealthFavorite(kind, id, !saved);
                    if (!mounted) return;
                    setState(() {
                      _favorites = widget.services.api.healthFavorites(
                        venueId: widget.venue.id,
                      );
                    });
                  } on BookingException catch (error) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(content: Text(s.bkError(error.failure))),
                    );
                  } finally {
                    if (mounted) setState(() => _saving.remove(key));
                  }
                },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final venue = widget.venue;
    final s = bkL10n(context);
    final canSave =
        venue.category == 'HEALTH' && widget.services.auth.authenticated;
    return Scaffold(
      appBar: AppBar(
        title: Text(venue.name),
        actions: [
          if (canSave)
            _favoriteButton(HealthFavoriteKind.organization, venue.id),
        ],
      ),
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
                  }),
                );
              }
              final detail = state.data!;
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  Container(
                    height: 120,
                    decoration: BoxDecoration(
                      color: toneColors(venue.tone).background,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    alignment: Alignment.center,
                    child: ExcludeSemantics(
                      child: Text(
                        venue.emoji,
                        style: const TextStyle(fontSize: 64),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          venue.name,
                          style: theme.textTheme.headlineSmall,
                        ),
                      ),
                      if (venue.synthetic) const DemoBadge(),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, size: 18),
                      const SizedBox(width: 4),
                      Expanded(child: Text(venue.addressText)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    venue.description,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(s.bkServices, style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  for (final service in detail.services)
                    _ServiceTile(
                      service: service,
                      enabled: venue.open &&
                          service.available &&
                          detail.mastersFor(service.id).isNotEmpty,
                      favorite: canSave && service.wellness
                          ? _favoriteButton(
                              HealthFavoriteKind.wellnessService, service.id)
                          : null,
                      onBook: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => BookingFlowScreen(
                            services: widget.services,
                            detail: detail,
                            service: service,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Text(
                    venue.category == 'HEALTH'
                        ? s.healthText('Специалисты', 'Мамандар', 'Specialists')
                        : s.bkMasters,
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  for (final m in detail.masters)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: EmojiTile(
                        emoji: m.emoji,
                        tone: m.tone,
                        size: 48,
                        radius: 14,
                      ),
                      title: Text(m.name),
                      subtitle: Text(m.bio),
                      trailing: canSave
                          ? _favoriteButton(HealthFavoriteKind.specialist, m.id)
                          : venue.category == 'HEALTH'
                              ? const Icon(Icons.chevron_right)
                              : null,
                      onTap: venue.category != 'HEALTH'
                          ? null
                          : () => Navigator.of(context).push<void>(
                                MaterialPageRoute(
                                  builder: (_) => HealthSpecialistScreen(
                                    services: widget.services,
                                    detail: detail,
                                    specialist: m,
                                  ),
                                ),
                              ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({
    required this.service,
    required this.enabled,
    required this.onBook,
    this.favorite,
  });

  final BookableService service;
  final bool enabled;
  final VoidCallback onBook;
  final Widget? favorite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = bkL10n(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.bkCatalogName(service.name),
                  style: theme.textTheme.titleMedium,
                ),
                if (service.description.isNotEmpty)
                  Text(
                    service.description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: 2),
                Text(
                  '${formatDuration(service.durationMinutes)} · ${formatTenge(service.priceMinor)}',
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (favorite != null) favorite!,
                FilledButton.tonal(
                  onPressed: enabled ? onBook : null,
                  child: Text(enabled ? s.bkBookAction : s.bkUnavailable),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
