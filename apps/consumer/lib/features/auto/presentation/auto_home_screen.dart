import 'dart:async';

import 'package:flutter/material.dart';

import '../auto_services.dart';
import '../data/auto_api.dart';
import 'package:kunde_models/auto_models.dart';
import 'auto_bookings_screen.dart';
import 'auto_strings.dart';
import 'auto_venue_screen.dart';
import 'auto_widgets.dart';
import 'vehicles_screen.dart';

/// Auto home: search, category filter, stations and car washes, shortcuts to cars and bookings.
class AutoHomeScreen extends StatefulWidget {
  const AutoHomeScreen({required this.services, super.key});

  final AutoServices services;

  @override
  State<AutoHomeScreen> createState() => _AutoHomeScreenState();
}

class _AutoHomeScreenState extends State<AutoHomeScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  String? _category;
  late Future<List<AutoCategory>> _categories =
      widget.services.api.categories();
  late Future<List<AutoVenue>> _venues = _load();

  Future<List<AutoVenue>> _load() =>
      widget.services.api.venues(category: _category, query: _search.text);

  void _reload() => setState(() {
        _venues = _load();
      });

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onQuery(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _reload);
  }

  @override
  Widget build(BuildContext context) {
    final s = auL10n(context);
    final theme = Theme.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    return Scaffold(
      appBar: AppBar(title: Text(s.auTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Text(s.auIntro, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                              builder: (_) =>
                                  VehiclesScreen(services: widget.services))),
                      icon: const Icon(Icons.directions_car_rounded),
                      label: Text(s.auMyVehicles))),
              const SizedBox(width: 8),
              Expanded(
                  child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                              builder: (_) => AutoBookingsScreen(
                                  services: widget.services))),
                      icon: const Icon(Icons.event_note_rounded),
                      label: Text(s.auMyBookings))),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _search,
              onChanged: _onQuery,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: s.auSearchHint,
                  border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            FutureBuilder<List<AutoCategory>>(
              future: _categories,
              builder: (context, snap) {
                final cats = snap.data ?? const <AutoCategory>[];
                return Wrap(spacing: 8, runSpacing: 4, children: [
                  ChoiceChip(
                      label: Text(s.auAllCategories),
                      selected: _category == null,
                      onSelected: (_) {
                        _category = null;
                        _reload();
                      }),
                  for (final c in cats.where((c) => c.enabled))
                    ChoiceChip(
                        label: Text(c.name(lang)),
                        selected: _category == c.code,
                        onSelected: (_) {
                          _category = c.code;
                          _reload();
                        }),
                ]);
              },
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<AutoVenue>>(
              future: _venues,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const SizedBox(
                      height: 160, child: AutoStateView.loading());
                }
                if (snap.hasError) {
                  final f = snap.error is AutoException
                      ? (snap.error as AutoException).failure
                      : AutoFailure.other;
                  return SizedBox(
                      height: 200,
                      child: AutoStateView.error(
                          error: f,
                          onRetry: () {
                            _categories = widget.services.api.categories();
                            _reload();
                          }));
                }
                final venues = snap.data!;
                if (venues.isEmpty) {
                  return SizedBox(
                      height: 200,
                      child: AutoStateView.empty(
                          emptyTitle: s.auNoVenues,
                          emptyBody: s.auNoVenuesBody));
                }
                return Column(children: [
                  for (final v in venues)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _VenueCard(
                            venue: v,
                            onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                    builder: (_) => AutoVenueScreen(
                                        services: widget.services,
                                        venueId: v.id))))),
                ]);
              },
            ),
            const SizedBox(height: 8),
            Text(s.auDemoNote,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }
}

class _VenueCard extends StatelessWidget {
  const _VenueCard({required this.venue, required this.onTap});

  final AutoVenue venue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = auL10n(context);
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: '${venue.name}, ${venue.addressText}',
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: theme.colorScheme.outlineVariant)),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(venue.name, style: theme.textTheme.titleLarge),
              const SizedBox(height: 2),
              Text(venue.addressText, style: theme.textTheme.bodyMedium),
              if (venue.rating != null)
                Text(s.auRating(
                    venue.rating!.toStringAsFixed(1), venue.reviews)),
              if (venue.fromPriceMinor != null) ...[
                const SizedBox(height: 8),
                Text(s.auFrom(formatTenge(venue.fromPriceMinor!)),
                    style: theme.textTheme.titleSmall),
              ],
              if (!venue.open)
                Text(s.auClosed,
                    style: TextStyle(color: theme.colorScheme.error)),
            ]),
          ),
        ),
      ),
    );
  }
}
