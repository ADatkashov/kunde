import 'dart:async';

import 'package:flutter/material.dart';

import '../data/food_api.dart';
import '../data/food_models.dart';
import '../food_services.dart';
import 'cart_screen.dart';
import 'food_widgets.dart';
import 'restaurant_screen.dart';

/// KUNDE Food: restaurant catalog with search over restaurants and dishes.
class FoodHomeScreen extends StatefulWidget {
  const FoodHomeScreen({required this.services, super.key});

  final FoodServices services;

  @override
  State<FoodHomeScreen> createState() => _FoodHomeScreenState();
}

class _FoodHomeScreenState extends State<FoodHomeScreen> {
  final _query = TextEditingController();
  Timer? _debounce;
  late Future<List<Restaurant>> _restaurants;
  Future<FoodSearchResult>? _search;
  String _term = '';

  @override
  void initState() {
    super.initState();
    _restaurants = widget.services.api.restaurants();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final term = value.trim();
      if (!mounted || term == _term) return;
      setState(() {
        _term = term;
        _search = term.isEmpty ? null : widget.services.api.search(term);
      });
    });
  }

  void _openRestaurant(Restaurant restaurant) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => RestaurantScreen(
              services: widget.services, restaurant: restaurant)));

  Future<void> _refresh() async {
    final next = widget.services.api.restaurants();
    setState(() {
      _restaurants = next;
    });
    try {
      await next;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Еда · Алматы'),
          actions: [
            ListenableBuilder(
              listenable: widget.services.cart,
              builder: (context, _) => IconButton(
                tooltip: 'Корзина',
                onPressed: widget.services.cart.isEmpty
                    ? null
                    : () => Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => CartScreen(services: widget.services))),
                icon: Badge(
                  isLabelVisible: !widget.services.cart.isEmpty,
                  label: Text('${widget.services.cart.itemCount}'),
                  child: const Icon(Icons.shopping_bag_outlined),
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: FoodCartBar(services: widget.services),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: SearchBar(
                  controller: _query,
                  hintText: 'Рестораны и блюда',
                  leading: const Icon(Icons.search_rounded),
                  trailing: [
                    if (_query.text.isNotEmpty)
                      IconButton(
                        tooltip: 'Очистить',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _query.clear();
                          _onChanged('');
                          setState(() {});
                        },
                      ),
                  ],
                  onChanged: (value) {
                    setState(() {});
                    _onChanged(value);
                  },
                  elevation: const WidgetStatePropertyAll(0),
                ),
              ),
              Expanded(child: _search == null ? _catalog() : _results()),
            ]),
          ),
        ),
      );

  Widget _catalog() => FutureBuilder<List<Restaurant>>(
        future: _restaurants,
        builder: (context, state) {
          if (state.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.hasError) {
            final message = state.error is FoodException
                ? (state.error as FoodException).message
                : null;
            return FoodStateMessage(
                icon: Icons.cloud_off_outlined,
                title: 'Не удалось загрузить рестораны',
                body: message,
                onAction: _refresh);
          }
          final list = state.data!;
          if (list.isEmpty) {
            return const FoodStateMessage(
                icon: Icons.storefront_outlined,
                title: 'Пока нет ресторанов',
                body: 'Рестораны появятся здесь, когда будут добавлены.');
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 14),
              itemBuilder: (context, i) => RestaurantCard(
                  restaurant: list[i], onTap: () => _openRestaurant(list[i])),
            ),
          );
        },
      );

  Widget _results() => FutureBuilder<FoodSearchResult>(
        future: _search,
        builder: (context, state) {
          if (state.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.hasError) {
            return FoodStateMessage(
                icon: Icons.cloud_off_outlined,
                title: 'Поиск не удался',
                onAction: () => setState(
                    () => _search = widget.services.api.search(_term)));
          }
          final result = state.data!;
          if (result.isEmpty) {
            return FoodStateMessage(
                icon: Icons.search_off_rounded,
                title: 'Ничего не найдено',
                body: 'По запросу «$_term» нет ресторанов и блюд.');
          }
          return ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                if (result.restaurants.isNotEmpty) ...[
                  Text('Рестораны',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final r in result.restaurants) ...[
                    RestaurantCard(
                        restaurant: r, onTap: () => _openRestaurant(r)),
                    const SizedBox(height: 12),
                  ],
                ],
                if (result.dishes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Блюда', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final d in result.dishes)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: EmojiTile(
                          emoji: d.emoji, tone: d.tone, size: 52, radius: 14),
                      title: Text(d.name),
                      subtitle: Text(
                          '${d.restaurantName} · ${formatTenge(d.priceMinor)}'
                          '${d.available ? '' : ' · нет в наличии'}'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () async {
                        final nav = Navigator.of(context);
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          final menu =
                              await widget.services.api.menu(d.restaurantId);
                          if (!mounted) return;
                          nav.push(MaterialPageRoute<void>(
                              builder: (_) => RestaurantScreen(
                                  services: widget.services,
                                  restaurant: menu.restaurant,
                                  preloaded: menu)));
                        } on FoodException catch (e) {
                          if (!mounted) return;
                          messenger
                              .showSnackBar(SnackBar(content: Text(e.message)));
                        }
                      },
                    ),
                ],
              ]);
        },
      );
}

/// Horizontal list of restaurants for the home screen ("Рядом с вами").
class FoodNearbySection extends StatefulWidget {
  const FoodNearbySection({required this.services, super.key});

  final FoodServices services;

  @override
  State<FoodNearbySection> createState() => _FoodNearbySectionState();
}

class _FoodNearbySectionState extends State<FoodNearbySection> {
  late Future<List<Restaurant>> _future = widget.services.api.restaurants();

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Restaurant>>(
        future: _future,
        builder: (context, state) {
          if (state.connectionState != ConnectionState.done) {
            return const SizedBox(
                height: 120, child: Center(child: CircularProgressIndicator()));
          }
          if (state.hasError || state.data!.isEmpty) {
            return Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.cloud_off_outlined),
                title: const Text('Не удалось загрузить рестораны'),
                trailing: TextButton(
                    onPressed: () => setState(
                        () => _future = widget.services.api.restaurants()),
                    child: const Text('Повторить')),
              ),
            );
          }
          final list = state.data!.take(6).toList();
          return SizedBox(
            height: 188,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final r = list[i];
                final colors = toneColors(r.tone);
                return SizedBox(
                  width: 168,
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    margin: EdgeInsets.zero,
                    child: InkWell(
                      onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                              builder: (_) => RestaurantScreen(
                                  services: widget.services, restaurant: r))),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                                height: 84,
                                width: double.infinity,
                                color: colors.background,
                                alignment: Alignment.center,
                                child: ExcludeSemantics(
                                    child: Text(r.emoji,
                                        style: const TextStyle(fontSize: 42)))),
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(r.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium),
                                    const SizedBox(height: 2),
                                    Text(
                                        r.open
                                            ? '${r.cuisine} · ${r.eta}'
                                            : 'Закрыто',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall),
                                  ]),
                            ),
                          ]),
                    ),
                  ),
                );
              },
            ),
          );
        },
      );
}
