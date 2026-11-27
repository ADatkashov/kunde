import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kunde_design/kunde_design.dart';

import 'package:kunde_localization/kunde_localizations.dart';
import 'package:kunde_localization/kunde_formats.dart';
import '../../home/presentation/home_strings.dart';
import '../data/food_api.dart';
import 'package:kunde_models/food_models.dart';
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
  RestaurantFilter _filter = const RestaurantFilter();
  final _query = TextEditingController();
  Timer? _debounce;
  late Future<List<Restaurant>> _restaurants;
  late Future<List<FoodPromotion>> _promotions;
  late Future<List<FoodCategory>> _categories;
  Future<FoodSearchResult>? _search;
  String _term = '';

  /// Ids of the caller's favorite restaurants; `null` while unknown or when the caller is signed out.
  Set<String>? _favorites;

  Future<List<Restaurant>> _load() => widget.services.api
      .restaurants(vertical: widget.vertical, filter: _filter);

  @override
  void initState() {
    super.initState();
    _restaurants = _load();
    _promotions = widget.services.api
        .promotions(vertical: widget.vertical)
        .catchError((_) => <FoodPromotion>[]);
    _categories = widget.services.api
        .categories(vertical: widget.vertical)
        .catchError((_) => <FoodCategory>[]);
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    if (_flowers) return;
    try {
      final list = await widget.services.api.favorites();
      if (mounted) setState(() => _favorites = {for (final r in list) r.id});
    } catch (_) {
      // Signed out or offline: the hearts simply stay hidden.
    }
  }

  Future<void> _toggleFavorite(Restaurant r) async {
    final current = _favorites;
    if (current == null) return;
    final next = !current.contains(r.id);
    setState(() =>
        _favorites = next ? {...current, r.id} : ({...current}..remove(r.id)));
    try {
      await widget.services.api.setFavorite(r.id, next);
    } on FoodException catch (error) {
      if (!mounted) return;
      setState(() => _favorites = current);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  void _applyFilter(RestaurantFilter next) {
    setState(() {
      _filter = next;
      _restaurants = _load();
    });
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
    final next = _load();
    setState(() {
      _restaurants = next;
    });
    try {
      await next;
    } catch (_) {}
  }

  Widget _cartAction({bool onDark = false}) => ListenableBuilder(
        listenable: widget.services.cart,
        builder: (context, _) => IconButton(
          tooltip: _tx('Корзина', 'Себет', 'Cart'),
          color: onDark ? Colors.white : null,
          onPressed: widget.services.cart.isEmpty
              ? null
              : () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => CartScreen(services: widget.services))),
          icon: Badge(
            isLabelVisible: !widget.services.cart.isEmpty,
            label: Text('${widget.services.cart.itemCount}'),
            child: Icon(Icons.shopping_bag_outlined,
                color: onDark && !widget.services.cart.isEmpty
                    ? Colors.white
                    : (onDark ? Colors.white54 : null)),
          ),
        ),
      );

  Widget _searchField() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: SearchBar(
          controller: _query,
          hintText: _flowers
              ? _tx(
                  'Найти цветы, подарки или магазин',
                  'Гүл, сыйлық немесе дүкен іздеу',
                  'Find flowers, gifts or a shop')
              : _grocery
                  ? _tx('Магазины и товары', 'Дүкендер мен тауарлар',
                      'Shops and products')
                  : 'Найти ресторан или блюдо',
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
      );

  /// The only supported city is shown as a read-only chip (no empty picker).
  Widget _cityChip() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.location_on_rounded,
                size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 4),
            const Text('Алматы',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (!_grocery || _flowers) {
      return Scaffold(
        bottomNavigationBar: FoodCartBar(services: widget.services),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(children: [
              FoodHeroHeader(
                title: _flowers ? _flowersTitle(context) : 'Еда',
                subtitle: _flowers
                    ? _tx(
                        'Букеты, подарки и приятные сюрпризы для ваших близких',
                        'Жақындарыңызға гүл шоқтары, сыйлықтар мен тосынсыйлар',
                        'Bouquets, gifts and pleasant surprises for loved ones')
                    : 'Рестораны, кафе и доставка еды',
                image: _flowers ? null : 'assets/photos/food-banner.webp',
                actions: [_cartAction(onDark: true)],
              ),
              Expanded(
                child: FoodSheet(
                  child: Column(children: [
                    _cityChip(),
                    _searchField(),
                    Expanded(child: _search == null ? _catalog() : _results()),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_flowers
            ? _flowersTitle(context)
            : (_grocery ? 'Продукты · Алматы' : 'Еда · Алматы')),
        actions: [_cartAction()],
      ),
      bottomNavigationBar: FoodCartBar(services: widget.services),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(children: [
            if (!_flowers) FoodCollectionHeader(grocery: _grocery),
            _searchField(),
            Expanded(child: _search == null ? _catalog() : _results()),
          ]),
        ),
      ),
    );
  }

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
          final list = state.data!;
          if (list.isEmpty && !_filter.isActive) {
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
                if (i == 0) return _header(foundCount: list.length);
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
                final r = list[i - 1];
                return RestaurantCard(
                    restaurant: r,
                    favorite: _favorites?.contains(r.id),
                    onFavorite: () => _toggleFavorite(r),
                    onTap: () => _openRestaurant(r));
              },
            ),
          );
        },
      );

  Widget _header({int? foundCount}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (!_flowers) _promoBanner(),
        if (!_flowers && !_grocery) _categoryRow(),
        _filters(),
        if (!_flowers && !_grocery && foundCount != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 12, 0, 0),
            child: Text('Найдено: $foundCount',
                key: const Key('found-count'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
      ]);

  /// The banner only exists when the server has an active promotion; it opens the real offer.
  Widget _promoBanner() => FutureBuilder<List<FoodPromotion>>(
        future: _promotions,
        builder: (context, state) {
          final promos = state.data ?? const <FoodPromotion>[];
          if (promos.isEmpty) return const SizedBox.shrink();
          final promo = promos.first;
          final theme = Theme.of(context);
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Semantics(
              button: true,
              label: 'Акция: ${promo.title}',
              child: Material(
                key: const Key('promo-banner'),
                color: KundePalette.violet,
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => _openPromotion(promo),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(promo.title,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800)),
                              if (promo.code != null)
                                Text('Промокод ${promo.code}',
                                    style: theme.textTheme.bodyMedium
                                        ?.copyWith(color: Colors.white)),
                            ]),
                      ),
                      Text(promo.valueLabel,
                          style: theme.textTheme.headlineSmall?.copyWith(
                              color: KundePalette.gold,
                              fontWeight: FontWeight.w900)),
                    ]),
                  ),
                ),
              ),
            ),
          );
        },
      );

  void _openPromotion(FoodPromotion promo) {
    final restaurantId = promo.restaurantId;
    if (restaurantId != null) {
      widget.services.api.menu(restaurantId).then((menu) {
        if (!mounted) return;
        Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => RestaurantScreen(
                services: widget.services,
                restaurant: menu.restaurant,
                preloaded: menu)));
      }).catchError((_) {});
      return;
    }
    // A promotion for every restaurant: show the conditions and the code to enter in the cart.
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(promo.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (promo.description.isNotEmpty) Text(promo.description),
              if (promo.code != null) ...[
                const SizedBox(height: 8),
                SelectableText('Промокод: ${promo.code}',
                    style: Theme.of(context).textTheme.titleMedium),
                const Text('Введите его в корзине при оформлении заказа.'),
              ],
            ]),
      ),
    );
  }

  /// Cuisines come from the backend (open restaurants per cuisine); tapping one filters on the server.
  Widget _categoryRow() => FutureBuilder<List<FoodCategory>>(
        future: _categories,
        builder: (context, state) {
          final list = state.data ?? const <FoodCategory>[];
          if (list.isEmpty) return const SizedBox.shrink();
          final colors = Theme.of(context).colorScheme;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: LayoutBuilder(builder: (context, box) {
              final columns =
                  box.maxWidth < 300 ? 2 : (box.maxWidth < 360 ? 3 : 4);
              final gap = 10.0;
              final width = (box.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(spacing: gap, runSpacing: gap, children: [
                for (final c in list)
                  SizedBox(
                    width: width,
                    child: Semantics(
                      button: true,
                      selected: _filter.cuisine == c.cuisine,
                      label: '${c.cuisine}, ${c.restaurants}',
                      child: Material(
                        key: Key('category-${c.cuisine}'),
                        color: _filter.cuisine == c.cuisine
                            ? colors.primaryContainer
                            : colors.surface,
                        borderRadius: BorderRadius.circular(16),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => _applyFilter(_filter.copyWith(
                              cuisine: _filter.cuisine == c.cuisine
                                  ? null
                                  : c.cuisine)),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 12, horizontal: 4),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: _filter.cuisine == c.cuisine
                                      ? colors.primary
                                      : colors.outlineVariant),
                            ),
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                        color: colors.primaryContainer
                                            .withValues(alpha: .6),
                                        shape: BoxShape.circle),
                                    child: Icon(Icons.restaurant_rounded,
                                        color: colors.primary),
                                  ),
                                  const SizedBox(height: 6),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(c.cuisine,
                                        maxLines: 1,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700)),
                                  ),
                                ]),
                          ),
                        ),
                      ),
                    ),
                  ),
              ]);
            }),
          );
        },
      );

  Widget _filters() {
    final sorts = <String, String>{
      'recommended': _tx('Рекомендуемые', 'Ұсынылған', 'Recommended'),
      'rating': _tx('По рейтингу', 'Рейтинг бойынша', 'By rating'),
      'eta': _tx('Быстрее доставка', 'Жылдам жеткізу', 'Fastest delivery'),
      'delivery_fee':
          _tx('Дешевле доставка', 'Арзан жеткізу', 'Lowest delivery fee'),
    };
    return SizedBox(
      height: 24 + MediaQuery.textScalerOf(context).scale(24),
      child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            PopupMenuButton<String>(
              key: const Key('sort-menu'),
              tooltip: _tx('Сортировка', 'Сұрыптау', 'Sort'),
              onSelected: (v) => _applyFilter(_filter.copyWith(sort: v)),
              itemBuilder: (_) => [
                for (final e in sorts.entries)
                  PopupMenuItem(value: e.key, child: Text(e.value)),
              ],
              child: Chip(
                avatar: const Icon(Icons.sort_rounded, size: 18),
                label: Text(_filter.sort == 'recommended'
                    ? _tx('Сортировка', 'Сұрыптау', 'Sort')
                    : sorts[_filter.sort]!),
              ),
            ),
            const SizedBox(width: 8),
            FilterChip(
              key: const Key('filter-open'),
              label: Text(_tx('Открыто сейчас', 'Қазір ашық', 'Open now')),
              selected: _filter.openNow,
              onSelected: (v) => _applyFilter(_filter.copyWith(openNow: v)),
            ),
            if (!_flowers) ...[
              const SizedBox(width: 8),
              FilterChip(
                key: const Key('filter-pickup'),
                label: const Text('Самовывоз'),
                selected: _filter.pickup,
                onSelected: (v) => _applyFilter(_filter.copyWith(pickup: v)),
              ),
              const SizedBox(width: 8),
              FilterChip(
                key: const Key('filter-free-delivery'),
                label: const Text('Бесплатная доставка'),
                selected: _filter.freeDelivery,
                onSelected: (v) =>
                    _applyFilter(_filter.copyWith(freeDelivery: v)),
              ),
              const SizedBox(width: 8),
              FilterChip(
                key: const Key('filter-promo'),
                label: const Text('Акции'),
                selected: _filter.promo,
                onSelected: (v) => _applyFilter(_filter.copyWith(promo: v)),
              ),
              const SizedBox(width: 8),
              FilterChip(
                key: const Key('filter-rating'),
                label: const Text('Рейтинг 4+'),
                selected: _filter.minRating == 4,
                onSelected: (v) =>
                    _applyFilter(_filter.copyWith(minRating: v ? 4 : null)),
              ),
            ],
            if (_filter.isActive) ...[
              const SizedBox(width: 8),
              ActionChip(
                key: const Key('filter-reset'),
                avatar: const Icon(Icons.close_rounded, size: 18),
                label: Text(_tx('Сбросить', 'Тазалау', 'Reset')),
                onPressed: () => _applyFilter(const RestaurantFilter()),
              ),
            ],
          ])),
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
          final s = KundeLocalizations.of(context);
          if (state.connectionState != ConnectionState.done) {
            return const SizedBox(
                height: 120, child: Center(child: CircularProgressIndicator()));
          }
          if (state.hasError) {
            return Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.cloud_off_outlined),
                title: Text(s.catalogRestaurantsError),
                trailing: TextButton(
                    onPressed: () => setState(
                        () => _future = widget.services.api.restaurants()),
                    child: Text(s.retry)),
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
            return Text(s.searchEmpty);
          }
          return SizedBox(
            height: 104 + MediaQuery.textScalerOf(context).scale(96),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final r = list[i];
                return SizedBox(
                  width: 154,
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
                                restaurant: r, height: 88, nearby: true),
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
                                            ? '${r.cuisine} · ${s.catalogEta(r.etaMinMinutes, r.etaMaxMinutes)}'
                                            : s.catalogClosed,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall),
                                    if (r.minOrderMinor > 0)
                                      Text(
                                        s.catalogMinOrder(KundeFormats.money(
                                          r.minOrderMinor,
                                          'KZT',
                                          Localizations.localeOf(context),
                                        )),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall,
                                      ),
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
