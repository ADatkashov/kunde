import 'package:flutter/material.dart';

import '../../food/data/food_models.dart' show toneColors;
import '../../food/presentation/food_widgets.dart';
import '../booking_services.dart';
import '../data/booking_api.dart';
import '../data/booking_models.dart';
import 'venue_screen.dart';

/// Barbershop list with loading skeleton, error retry and empty state.
class VenueListScreen extends StatefulWidget {
  const VenueListScreen({required this.services, super.key});

  final BookingServices services;

  @override
  State<VenueListScreen> createState() => _VenueListScreenState();
}

class _VenueListScreenState extends State<VenueListScreen> {
  late Future<List<BookingVenue>> _venues = widget.services.api.venues();

  Future<void> _refresh() async {
    final next = widget.services.api.venues();
    setState(() {
      _venues = next;
    });
    try {
      await next;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Барбершопы')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: FutureBuilder<List<BookingVenue>>(
              future: _venues,
              builder: (context, state) {
                if (state.connectionState != ConnectionState.done) {
                  return const RestaurantListSkeleton();
                }
                if (state.hasError) {
                  final error = state.error;
                  return FoodStateMessage(
                      icon: Icons.cloud_off_outlined,
                      title: 'Не удалось загрузить барбершопы',
                      body: error is BookingException ? error.message : null,
                      onAction: _refresh);
                }
                final list = state.data!;
                if (list.isEmpty) {
                  return const FoodStateMessage(
                      icon: Icons.storefront_outlined,
                      title: 'Пока нет барбершопов',
                      body: 'Заведения появятся здесь, когда будут добавлены.');
                }
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 14),
                    itemBuilder: (context, i) => _VenueCard(
                      venue: list[i],
                      onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                              builder: (_) => VenueScreen(
                                  services: widget.services, venue: list[i]))),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
}

class _VenueCard extends StatelessWidget {
  const _VenueCard({required this.venue, required this.onTap});

  final BookingVenue venue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = toneColors(venue.tone);
    return Semantics(
      button: true,
      label: '${venue.name}, ${venue.addressText}',
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: theme.colorScheme.outlineVariant)),
        child: InkWell(
          onTap: onTap,
          child: Opacity(
            opacity: venue.open ? 1 : 0.55,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                height: 96,
                width: double.infinity,
                color: colors.background,
                alignment: Alignment.center,
                child: Stack(alignment: Alignment.center, children: [
                  ExcludeSemantics(
                      child: Text(venue.emoji,
                          style: const TextStyle(fontSize: 52))),
                  if (venue.synthetic)
                    const Positioned(left: 12, top: 12, child: DemoBadge()),
                  if (!venue.open)
                    Positioned(
                        right: 12,
                        top: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(999)),
                          child: const Text('Закрыто',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 12)),
                        )),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(venue.name, style: theme.textTheme.titleLarge),
                      const SizedBox(height: 2),
                      Text(venue.addressText,
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 8),
                      if (venue.fromPriceMinor != null)
                        Text('Услуги от ${formatTenge(venue.fromPriceMinor!)}',
                            style: theme.textTheme.titleSmall),
                    ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
