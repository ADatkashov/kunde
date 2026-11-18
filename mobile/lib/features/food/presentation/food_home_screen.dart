import '../../../core/localization/kunde_localizations.dart';
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
  const FoodHomeScreen(
      {required this.services, this.vertical = 'FOOD', super.key});

  final FoodServices services;

  /// `FOOD` (restaurants) or `GROCERY` (stores).
  final String vertical;

  @override
  State<FoodHomeScreen> createState() => _FoodHomeScreenState();
}

class _FoodHomeScreenState extends State<FoodHomeScreen> {
  bool get _flowers => widget.vertical == 'FLOWERS_GIFTS';
  bool get _grocery => widget.vertical != 'FOOD';

  String _tx(String ru, String kk, String en) {
    if (!_flowers) return ru;
    return switch (Localizations.localeOf(context).languageCode) {
      'kk' => kk,
      'en' => en,
      _ => ru,
    };
  }

  String _flowersTitle(BuildContext context) =>
      switch (Localizations.localeOf(context).languageCode) {
        'kk' => 'Гүлдер мен сыйлықтар',
        'en' => 'Flowers & gifts',
        _ => 'Цветы и подарки',
      };
  bool _openOnly = false;
  String? _cuisine;
  String _sort = 'default';
  final _query = TextEditingController();
  Timer? _debounce;
  late Future<List<Restaurant>> _restaurants;
  Future<FoodSearchResult>? _search;
  String _term = '';

  @override
  void initState() {
    super.initState();
    _restaurants = widget.services.api.restaurants(vertical: widget.vertical);
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
        _search = term.isEmpty
            ? null
            : widget.services.api.search(term, vertical: widget.vertical);
      });
    });
  }

  void _openRestaurant(Restaurant restaurant) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => RestaurantScreen(
              services: widget.services, restaurant: restaurant)));

  Future<void> _refresh() async {
    final next = widget.services.api.restaurants(vertical: widget.vertical);
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
          title: Text(_flowers
              ? _flowersTitle(context)
              : (_grocery ? 'Продукты · Алматы' : 'Еда · Алматы')),
          actions: [
            ListenableBuilder(
              listenable: widget.services.cart,
              builder: (context, _) => IconButton(
                tooltip: _tx('Корзина', 'Себет', 'Cart'),
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
              if (!_flowers) FoodCollectionHeader(grocery: _grocery),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: SearchBar(
                  controller: _query,
                  hintText: _grocery
                      ? _tx('Магазины и товары', 'Дүкендер мен тауарлар',
                          'Shops and products')
                      : 'Рестораны и блюда',
                  leading: const Icon(Icons.search_rounded),
                  trailing: [
                    if (_query.text.isNotEmpty)
                      IconButton(
                        tooltip: _tx('Очистить', 'Тазалау', 'Clear'),
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
            return const RestaurantListSkeleton();
          }
          if (state.hasError) {
            final message = state.error is FoodException
                ? (state.error as FoodException).message
                : null;
            return FoodStateMessage(
                icon: Icons.cloud_off_outlined,
                title: _grocery
                    ? _tx('Не удалось загрузить магазины',
                        'Дүкендер жүктелмеді', 'Could not load shops')
                    : 'Не удалось загрузить рестораны',
                body: message,
                onAction: _refresh);
          }
          final all = state.data!;
          final list = _filtered(all);
          if (all.isEmpty) {
            return FoodStateMessage(
                icon: Icons.storefront_outlined,
                title: _grocery
                    ? _tx('Пока нет магазинов', 'Дүкендер әзірге жоқ',
                        'No shops yet')
                    : 'Пока нет ресторанов',
                body: _grocery
                    ? _tx(
                        'Магазины появятся здесь, когда будут добавлены.',
                        'Дүкендер қосылғанда осында көрсетіледі.',
                        'Shops will appear here once added.')
                    : 'Рестораны появятся здесь, когда будут добавлены.');
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: list.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 14),
              itemBuilder: (context, i) {
                if (i == 0) return _filters(all);
                if (list.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                        _tx(
                            'По выбранным фильтрам ничего нет.',
                            'Таңдалған сүзгілер бойынша ештеңе табылмады.',
                            'No results for these filters.'),
                        textAlign: TextAlign.center),
                  );
                }
                return RestaurantCard(
                    restaurant: list[i - 1],
                    onTap: () => _openRestaurant(list[i - 1]));
              },
            ),
          );
        },
      );

  List<Restaurant> _filtered(List<Restaurant> all) {
    final list = all
        .where((r) =>
            (!_openOnly || r.open) &&
            (_cuisine == null || r.cuisine == _cuisine))
        .toList();
    switch (_sort) {
      case 'eta':
        list.sort((a, b) => a.etaMinMinutes.compareTo(b.etaMinMinutes));
      case 'fee':
        list.sort((a, b) => a.deliveryFeeMinor.compareTo(b.deliveryFeeMinor));
    }
    return list;
  }

  Widget _filters(List<Restaurant> all) {
    final cuisines = {for (final r in all) r.cuisine}.toList()..sort();
    return SizedBox(
      height: 24 + MediaQuery.textScalerOf(context).scale(24),
      child: ListView(scrollDirection: Axis.horizontal, children: [
        FilterChip(
          label: Text(_tx('Открыто сейчас', 'Қазір ашық', 'Open now')),
          selected: _openOnly,
          onSelected: (v) => setState(() => _openOnly = v),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          tooltip: _tx('Сортировка', 'Сұрыптау', 'Sort'),
          onSelected: (v) => setState(() => _sort = v),
          itemBuilder: (_) => [
            PopupMenuItem(
                value: 'default',
                child: Text(_tx('По умолчанию', 'Әдепкі', 'Default'))),
            PopupMenuItem(
                value: 'eta',
                child: Text(_tx(
                    'Быстрее доставка', 'Жылдам жеткізу', 'Fastest delivery'))),
            PopupMenuItem(
                value: 'fee',
                child: Text(_tx('Дешевле доставка', 'Арзан жеткізу',
                    'Lowest delivery fee'))),
          ],
          child: Chip(
            avatar: const Icon(Icons.sort_rounded, size: 18),
            label: Text(switch (_sort) {
              'eta' =>
                _tx('Быстрее доставка', 'Жылдам жеткізу', 'Fastest delivery'),
              'fee' =>
                _tx('Дешевле доставка', 'Арзан жеткізу', 'Lowest delivery fee'),
              _ => _tx('Сортировка', 'Сұрыптау', 'Sort'),
            }),
          ),
        ),
        for (final c in cuisines) ...[
          const SizedBox(width: 8),
          ChoiceChip(
            label: Text(c),
            selected: _cuisine == c,
            onSelected: (v) => setState(() => _cuisine = v ? c : null),
          ),
        ],
      ]),
    );
  }

  Widget _results() => FutureBuilder<FoodSearchResult>(
        future: _search,
        builder: (context, state) {
          if (state.connectionState != ConnectionState.done) {
            return const RestaurantListSkeleton(count: 3);
          }
          if (state.hasError) {
            return FoodStateMessage(
                icon: Icons.cloud_off_outlined,
                title: _tx(
                    'Поиск не удался', 'Іздеу орындалмады', 'Search failed'),
                onAction: () => setState(() => _search = widget.services.api
                    .search(_term, vertical: widget.vertical)));
          }
          final result = state.data!;
          if (result.isEmpty) {
            return FoodStateMessage(
                icon: Icons.search_off_rounded,
                title:
                    _tx('Ничего не найдено', 'Ештеңе табылмады', 'No results'),
                body: _grocery
                    ? _tx(
                        'По запросу «$_term» нет магазинов и товаров.',
                        '«$_term» бойынша дүкендер мен тауарлар табылмады.',
                        'No shops or products found for “$_term”.')
                    : 'По запросу «$_term» нет ресторанов и блюд.');
          }
          return ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                if (result.restaurants.isNotEmpty) ...[
                  Text(
                      _flowers
                          ? _tx('Магазины', 'Дүкендер', 'Shops')
                          : 'Рестораны',
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
                  Text(
                      _grocery
                          ? _tx('Товары', 'Тауарлар', 'Products')
                          : 'Блюда',
                      style: Theme.of(context).textTheme.titleMedium),
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
  const FoodNearbySection(
      {required this.services,
      this.query = '',
      this.openOnly = false,
      super.key});

  final FoodServices services;
  final String query;
  final bool openOnly;

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
          final query = widget.query.trim().toLowerCase();
          final list = state.data!
              .where((restaurant) {
                return (!widget.openOnly || restaurant.open) &&
                    (restaurant.name.toLowerCase().contains(query) ||
                        restaurant.cuisine.toLowerCase().contains(query));
              })
              .take(6)
              .toList();
          if (list.isEmpty) {
            return Text(KundeLocalizations.of(context).searchEmpty);
          }
          return SizedBox(
            height: 104 + MediaQuery.textScalerOf(context).scale(72),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final r = list[i];
                return SizedBox(
                  width: 136,
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
                            MerchantArtwork(
                                restaurant: r, height: 80, nearby: true),
                            Padding(
                              padding: const EdgeInsets.all(8),
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
                                    if (r.synthetic) const DemoBadge(),
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
