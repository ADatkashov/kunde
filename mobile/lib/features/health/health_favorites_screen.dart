import 'package:flutter/material.dart';

import '../booking/booking_services.dart';
import '../booking/data/booking_api.dart';
import '../booking/data/booking_models.dart';
import '../booking/presentation/booking_strings.dart';
import '../booking/presentation/venue_screen.dart';
import '../food/presentation/food_widgets.dart';

class HealthFavoritesScreen extends StatefulWidget {
  const HealthFavoritesScreen({required this.services, super.key});

  final BookingServices services;

  @override
  State<HealthFavoritesScreen> createState() => _HealthFavoritesScreenState();
}

class _HealthFavoritesScreenState extends State<HealthFavoritesScreen> {
  late Future<List<HealthFavorite>> _favorites =
      widget.services.api.healthFavorites();
  bool _busy = false;

  void _reload() {
    final favorites = widget.services.api.healthFavorites();
    setState(() {
      _favorites = favorites;
    });
  }

  Future<void> _act(HealthFavorite item, {required bool remove}) async {
    setState(() => _busy = true);
    try {
      if (remove) {
        await widget.services.api.setHealthFavorite(item.kind, item.id, false);
      } else {
        final detail = await widget.services.api.venue(item.venueId);
        if (!mounted) return;
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => VenueScreen(
              services: widget.services,
              venue: detail.venue,
            ),
          ),
        );
      }
      if (mounted) _reload();
    } on BookingException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(bkL10n(context).bkError(error.failure))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = bkL10n(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.healthText('Избранное', 'Таңдаулы', 'Favorites')),
      ),
      body: FutureBuilder<List<HealthFavorite>>(
        future: _favorites,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const RestaurantListSkeleton(count: 3);
          }
          if (snapshot.hasError) {
            return FoodStateMessage(
              icon: Icons.cloud_off_outlined,
              title: s.healthText(
                'Избранное недоступно',
                'Таңдаулы тізімі қолжетімсіз',
                'Favorites unavailable',
              ),
              actionLabel: s.bkRetry,
              onAction: _reload,
            );
          }
          final items = snapshot.requireData;
          if (items.isEmpty) {
            return FoodStateMessage(
              icon: Icons.favorite_border,
              title: s.healthText(
                'Избранное пока пусто',
                'Таңдаулы тізімі әзірге бос',
                'No favorites yet',
              ),
            );
          }
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final kind = switch (item.kind) {
                HealthFavoriteKind.organization =>
                  s.healthText('Организация', 'Ұйым', 'Organization'),
                HealthFavoriteKind.specialist =>
                  s.healthText('Специалист', 'Маман', 'Specialist'),
                HealthFavoriteKind.wellnessService => s.healthText(
                    'Оздоровительная услуга',
                    'Сауықтыру қызметі',
                    'Wellness service',
                  ),
              };
              return ListTile(
                title: Text(item.name),
                subtitle: Text(kind),
                onTap: _busy ? null : () => _act(item, remove: false),
                trailing: IconButton(
                  tooltip: s.healthText(
                    'Убрать из избранного',
                    'Таңдаулыдан өшіру',
                    'Remove from favorites',
                  ),
                  onPressed: _busy ? null : () => _act(item, remove: true),
                  icon: const Icon(Icons.favorite),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
