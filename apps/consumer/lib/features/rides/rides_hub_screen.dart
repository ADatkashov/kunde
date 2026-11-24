import 'package:flutter/material.dart';
import 'package:kunde_design/kunde_design.dart';

import 'package:kunde_maps/kunde_maps.dart';
import 'package:kunde_api/ride_api.dart';
import 'package:kunde_ui/ride_strings.dart';
import 'rides_screen.dart';

/// Entry point of the Rides product: the category hub. Only city rides have a
/// backend contract today; the other categories are listed as unavailable
/// instead of opening a fake flow.
class RidesHubScreen extends StatelessWidget {
  const RidesHubScreen({required this.api, this.maps, super.key});

  final RideApi api;
  final KundeMaps? maps;

  static const _categories = <(String, IconData, bool)>[
    ('city', Icons.directions_car_filled_rounded, true),
    ('airport', Icons.flight_rounded, false),
    ('intercity', Icons.add_road_rounded, false),
    ('rental', Icons.key_rounded, false),
    ('courier', Icons.inventory_2_rounded, false),
  ];

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    final theme = Theme.of(context);
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            decoration:
                const BoxDecoration(gradient: KundePalette.heroGradient),
            padding: EdgeInsets.fromLTRB(
              20,
              MediaQuery.paddingOf(context).top + 8,
              20,
              28,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BackButton(color: Colors.white),
                const SizedBox(height: 12),
                Semantics(
                  header: true,
                  child: Text(
                    s.rides,
                    style: theme.textTheme.headlineLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  s.hubTagline,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                for (final (key, icon, available) in _categories)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    // Own semantics boundary per tile, else all tiles merge
                    // into one accessibility node (TalkBack, UI tests).
                    child: Semantics(
                      container: true,
                      child: _HubTile(
                        icon: icon,
                        title: s.hubTitle(key),
                        subtitle: s.hubSubtitle(key),
                        available: available,
                        soon: s.soon,
                        onTap: available ? () => _openCity(context) : null,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openCity(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => RidesScreen(api: api, maps: maps)),
    );
  }
}

class _HubTile extends StatelessWidget {
  const _HubTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.available,
    required this.soon,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool available;
  final String soon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final muted = !available;
    return Material(
      color: scheme.surface,
      elevation: muted ? 0 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                icon,
                size: 30,
                color: muted ? scheme.onSurfaceVariant : scheme.primary,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: muted ? scheme.onSurfaceVariant : null,
                      ),
                    ),
                    Text(subtitle, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              if (muted)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(soon, style: theme.textTheme.labelSmall),
                )
              else
                Icon(Icons.chevron_right_rounded,
                    color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
