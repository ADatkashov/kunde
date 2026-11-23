import 'package:flutter/material.dart';

import '../../../core/localization/kunde_localizations.dart';
import '../../booking/booking_services.dart';
import '../beauty_strings.dart';
import '../beauty_theme.dart';
import '../data/beauty_models.dart';
import 'beauty_salon_screen.dart';
import 'beauty_support.dart';
import 'beauty_widgets.dart';

/// The customer's favorite salons.
class BeautyFavoritesScreen extends StatelessWidget {
  const BeautyFavoritesScreen(
      {required this.services, required this.favorites, super.key});

  final BookingServices services;
  final BeautyFavorites favorites;

  Future<List<BeautySalon>> _load() async {
    await favorites.load();
    final all = <BeautySalon>[];
    const page = 50;
    for (var offset = 0;; offset += page) {
      final result = await services.beauty
          .salons(const BeautySalonQuery(), limit: page, offset: offset);
      all.addAll(result.salons);
      if (all.length >= result.total || result.salons.isEmpty) break;
    }
    return all;
  }

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.bFavorites)),
      body: BeautyAsync<List<BeautySalon>>(
        load: _load,
        builder: (context, salons) => ListenableBuilder(
          listenable: favorites,
          builder: (context, _) {
            final mine =
                salons.where((salon) => favorites.contains(salon.id)).toList();
            if (mine.isEmpty) {
              return BeautyEmptyView(
                  icon: Icons.favorite_border, title: s.bFavoritesEmpty);
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 24),
              children: [
                for (final salon in mine)
                  BeautySalonCard(
                    salon: salon,
                    favorite: true,
                    onTap: () => Navigator.of(context).push(beautyRoute(
                      BeautySalonScreen(
                          services: services,
                          favorites: favorites,
                          salon: salon),
                    )),
                    onFavorite: () =>
                        toggleFavorite(context, favorites, salon.id),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
