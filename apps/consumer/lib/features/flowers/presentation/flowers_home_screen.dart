import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kunde_ui/ride_strings.dart';

import 'package:kunde_auth/auth_repository.dart';

import '../../home/data/kunde_api.dart';
import '../data/flowers_models.dart';
import '../data/flowers_services.dart';
import 'flowers_cart_screen.dart';
import 'flowers_order_screen.dart';
import 'flowers_shop_screen.dart';
import 'flowers_widgets.dart';

/// Flowers & Gifts home (ADR-026): violet hero with search, category grid, popular products and shops.
/// Shown only when the server reports `flowersEnabled`; ordering arrives with the next steps of the ADR.
class FlowersHomeScreen extends StatefulWidget {
  const FlowersHomeScreen({required this.api, this.auth, super.key});

  final KundeApi api;

  /// Signed-in session for ordering; without it the catalogue is read-only.
  final AuthRepository? auth;

  @override
  State<FlowersHomeScreen> createState() => _FlowersHomeScreenState();
}

class _FlowersHomeScreenState extends State<FlowersHomeScreen> {
  late final FlowersServices _services =
      FlowersServices(api: widget.api, auth: widget.auth);
  final _query = TextEditingController();
  Timer? _debounce;
  String? _category;
  String _term = '';
  late final Future<List<FlowersCategory>> _categories = _loadCategories();
  late final Future<List<FlowersProduct>> _popular = _loadPopular();
  late Future<List<FlowersShop>> _shops = _loadShops();

  Future<List<FlowersCategory>> _loadCategories() async => [
        for (final c
            in await widget.api.flowersJson('categories') as List<dynamic>)
          FlowersCategory.fromJson(c as Map<String, dynamic>),
      ];

  Future<List<FlowersProduct>> _loadPopular() async => [
        for (final p in await widget.api.flowersJson('products/popular')
            as List<dynamic>)
          FlowersProduct.fromJson(p as Map<String, dynamic>),
      ];

  Future<List<FlowersShop>> _loadShops() async => [
        for (final s in await widget.api.flowersJson('shops', {
          if (_category != null) 'category': _category!,
          if (_term.isNotEmpty) 'q': _term,
        }) as List<dynamic>)
          FlowersShop.fromJson(s as Map<String, dynamic>),
      ];

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _reload() => setState(() {
        _shops = _loadShops();
      });

  void _onQuery(String value) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final term = value.trim();
      if (!mounted || term == _term) return;
      _term = term;
      _reload();
    });
  }

  void _openShop(String id) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => FlowersShopScreen(services: _services, shopId: id)));

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(children: [
            FlowersHero(
              actions: [
                if (_services.orders != null)
                  IconButton(
                    key: const ValueKey('orders'),
                    tooltip:
                        s.t('Мои заказы', 'Менің тапсырыстарым', 'My orders'),
                    color: Colors.white,
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) =>
                                FlowersOrdersScreen(services: _services))),
                    icon: const Icon(Icons.receipt_long_outlined),
                  ),
                ListenableBuilder(
                  listenable: _services.cart,
                  builder: (context, _) => IconButton(
                    key: const ValueKey('cart'),
                    tooltip: s.t('Корзина', 'Себет', 'Cart'),
                    color: Colors.white,
                    onPressed: _services.cart.isEmpty
                        ? null
                        : () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                                builder: (_) =>
                                    FlowersCartScreen(services: _services))),
                    icon: Badge(
                      isLabelVisible: !_services.cart.isEmpty,
                      label: Text('${_services.cart.itemCount}'),
                      child: Icon(Icons.shopping_bag_outlined,
                          color: _services.cart.isEmpty
                              ? Colors.white54
                              : Colors.white),
                    ),
                  ),
                ),
              ],
              title: s.t(
                  'Цветы и подарки', 'Гүлдер мен сыйлықтар', 'Flowers & gifts'),
              subtitle: s.t(
                  'Букеты, подарки и приятные сюрпризы для ваших близких',
                  'Жақындарыңызға гүл шоқтары, сыйлықтар мен тосынсыйлар',
                  'Bouquets, gifts and pleasant surprises for loved ones'),
            ),
            Expanded(
              child: FlowersSheet(
                child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    children: [
                      Row(children: [
                        Icon(Icons.location_on_rounded,
                            size: 18,
                            color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 4),
                        const Text('Алматы',
                            style: TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 15)),
                      ]),
                      const SizedBox(height: 10),
                      SearchBar(
                        key: const ValueKey('search'),
                        controller: _query,
                        hintText: s.t(
                            'Найти цветы, подарок или магазин',
                            'Гүл, сыйлық немесе дүкен іздеу',
                            'Find flowers, gifts or a shop'),
                        leading: const Icon(Icons.search_rounded),
                        elevation: const WidgetStatePropertyAll(0),
                        onChanged: _onQuery,
                      ),
                      const SizedBox(height: 16),
                      _categoryGrid(s),
                      _popularSection(s),
                      const SizedBox(height: 8),
                      _shopsSection(s),
                    ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _categoryGrid(RideStrings s) => FutureBuilder<List<FlowersCategory>>(
        future: _categories,
        builder: (context, state) {
          final list = state.data ?? const <FlowersCategory>[];
          if (list.isEmpty) return const SizedBox.shrink();
          final colors = Theme.of(context).colorScheme;
          return LayoutBuilder(builder: (context, box) {
            const columns = 4;
            const gap = 10.0;
            final width = (box.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(spacing: gap, runSpacing: gap, children: [
              for (final c in list)
                SizedBox(
                  width: width,
                  child: Semantics(
                    button: true,
                    selected: _category == c.code,
                    label: c.name(s.language),
                    child: InkWell(
                      key: ValueKey('category-${c.code}'),
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        _category = _category == c.code ? null : c.code;
                        _reload();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 10, horizontal: 2),
                        decoration: BoxDecoration(
                          color: _category == c.code
                              ? colors.primaryContainer
                              : colors.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: _category == c.code
                                  ? colors.primary
                                  : colors.outlineVariant
                                      .withValues(alpha: .6)),
                        ),
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(flowersCategoryIcon(c.icon),
                              color: colors.primary, size: 28),
                          const SizedBox(height: 6),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(c.name(s.language),
                                maxLines: 1,
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w700)),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
            ]);
          });
        },
      );

  Widget _popularSection(RideStrings s) => FutureBuilder<List<FlowersProduct>>(
        future: _popular,
        builder: (context, state) {
          final list = state.data ?? const <FlowersProduct>[];
          if (list.isEmpty || _category != null || _term.isNotEmpty) {
            return const SizedBox.shrink();
          }
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                Text(s.t('Популярное', 'Танымал', 'Popular'),
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                SizedBox(
                  height: 196,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, i) => FlowersProductCard(
                        product: list[i],
                        onTap: () => _openShop(list[i].shopId)),
                  ),
                ),
              ]);
        },
      );

  Widget _shopsSection(RideStrings s) => FutureBuilder<List<FlowersShop>>(
        future: _shops,
        builder: (context, state) {
          if (state.connectionState != ConnectionState.done) {
            return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()));
          }
          if (state.hasError) {
            return Column(children: [
              Text(s.error),
              TextButton(onPressed: _reload, child: Text(s.retry)),
            ]);
          }
          final shops = state.data!;
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                Text(s.t('Магазины', 'Дүкендер', 'Shops'),
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text('${s.t('Найдено', 'Табылды', 'Found')}: ${shops.length}',
                    key: const ValueKey('found-count'),
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                if (shops.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                        child: Text(s.t('Пока нет магазинов',
                            'Дүкендер әзірге жоқ', 'No shops yet'))),
                  ),
                for (final shop in shops) ...[
                  FlowersShopCard(shop: shop, onTap: () => _openShop(shop.id)),
                  const SizedBox(height: 12),
                ],
              ]);
        },
      );
}
