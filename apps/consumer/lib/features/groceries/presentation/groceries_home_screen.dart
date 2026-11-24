import 'package:flutter/material.dart';
import 'package:kunde_design/kunde_design.dart';

import '../../food/presentation/food_widgets.dart';
import '../data/groceries_api.dart';
import '../data/groceries_models.dart';
import '../data/groceries_services.dart';
import 'catalog_screen.dart';
import 'grocery_widgets.dart';
import 'groceries_strings.dart';
import 'lists_screen.dart';
import 'product_screen.dart';

/// KUNDE Groceries home: photo hero with the title, city and search, the four quick actions (deals, new, my lists,
/// favorites), categories from the server taxonomy and real product shelves (discounts, new, popular). Every tile
/// opens a real catalog query; nothing is decorative.
class GroceriesHomeScreen extends StatefulWidget {
  const GroceriesHomeScreen({required this.services, super.key});

  final GroceriesServices services;

  @override
  State<GroceriesHomeScreen> createState() => _GroceriesHomeScreenState();
}

class _Shelves {
  const _Shelves(this.categories, this.discounts, this.fresh, this.popular);

  final List<GroceryCategory> categories;
  final List<GroceryProduct> discounts;
  final List<GroceryProduct> fresh;
  final List<GroceryProduct> popular;
}

class _GroceriesHomeScreenState extends State<GroceriesHomeScreen> {
  late Future<_Shelves> _future;

  GroceriesServices get _services => widget.services;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _services.loadFavorites();
    _services.cartSync.attach();
    _services.cartSync.restore(_services.storeFor).catchError((_) => false);
  }

  Future<_Shelves> _load() async {
    final api = _services.api;
    final results = await Future.wait([
      api.categories(),
      api.products(const ProductQuery(onSale: true, sort: 'discount'),
          limit: 10),
      api.products(const ProductQuery(newOnly: true, sort: 'new'), limit: 10),
      api.products(const ProductQuery(inStock: true), limit: 10),
    ]);
    return _Shelves(
      results[0] as List<GroceryCategory>,
      (results[1] as ProductsPage).items,
      (results[2] as ProductsPage).items,
      (results[3] as ProductsPage).items,
    );
  }

  void _reload() => setState(() {
        _future = _load();
      });

  void _openCatalog(ProductQuery query, String title,
          {bool autofocus = false}) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => CatalogScreen(
            services: _services,
            initial: query,
            title: title,
            autofocusSearch: autofocus),
      ));

  void _openProduct(GroceryProduct product) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) =>
            ProductScreen(services: _services, productId: product.id),
      ));

  @override
  Widget build(BuildContext context) {
    final s = GStr.of(context);
    return Scaffold(
      bottomNavigationBar: FoodCartBar(services: _services.food),
      body: FutureBuilder<_Shelves>(
        future: _future,
        builder: (context, snapshot) {
          final body = switch (snapshot.connectionState) {
            ConnectionState.done when snapshot.hasError =>
              _error(snapshot.error!, s),
            ConnectionState.done => _content(snapshot.data!, s),
            _ => _loading(),
          };
          return RefreshIndicator(
            onRefresh: () async {
              _reload();
              await _future.catchError((_) => const _Shelves([], [], [], []));
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                    child: _Hero(
                        title: s.title,
                        subtitle: s.subtitle,
                        city: s.city,
                        searchHint: s.searchHint,
                        onSearch: () => _openCatalog(
                            const ProductQuery(), s.title,
                            autofocus: true))),
                ...body,
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _loading() => const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(children: [
              SkeletonBox(height: 84, radius: 20),
              SizedBox(height: 16),
              SkeletonBox(height: 120, radius: 20),
              SizedBox(height: 16),
              SkeletonBox(height: 160, radius: 20),
            ]),
          ),
        ),
      ];

  List<Widget> _error(Object error, GStr s) {
    final failure = error is GroceriesException ? error.failure : null;
    final disabled = failure == GroceriesFailure.disabled;
    return [
      SliverFillRemaining(
        hasScrollBody: false,
        child: GroceryMessage(
          icon:
              disabled ? Icons.pause_circle_outline : Icons.cloud_off_outlined,
          title: disabled
              ? s.disabledTitle
              : (error is GroceriesException
                  ? error.messageFor(s.language)
                  : s.retry),
          body: disabled ? s.disabledBody : null,
          actionLabel: disabled ? null : s.retry,
          onAction: disabled ? null : _reload,
        ),
      ),
    ];
  }

  List<Widget> _content(_Shelves data, GStr s) => [
        SliverToBoxAdapter(
            child: _QuickActions(
          items: [
            (
              Icons.percent,
              s.promos,
              () => _openCatalog(
                  const ProductQuery(onSale: true, sort: 'discount'), s.promos)
            ),
            (
              Icons.fiber_new_outlined,
              s.newItems,
              () => _openCatalog(
                  const ProductQuery(newOnly: true, sort: 'new'), s.newItems)
            ),
            (
              Icons.checklist_rtl,
              s.myLists,
              () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => ListsScreen(services: _services)))
            ),
            (
              Icons.favorite_border,
              s.favorites,
              () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => FavoritesScreen(services: _services)))
            ),
          ],
        )),
        SliverToBoxAdapter(child: _SectionTitle(s.categories)),
        SliverToBoxAdapter(
          child: _CategoryGrid(
            categories: data.categories,
            language: s.language,
            onTap: (c) => _openCatalog(
                ProductQuery(category: c.slug), c.name(s.language)),
          ),
        ),
        if (data.discounts.isNotEmpty)
          ..._shelf(
              s.discounts,
              data.discounts,
              () => _openCatalog(
                  const ProductQuery(onSale: true, sort: 'discount'),
                  s.discounts)),
        if (data.fresh.isNotEmpty)
          ..._shelf(
              s.newItems,
              data.fresh,
              () => _openCatalog(
                  const ProductQuery(newOnly: true, sort: 'new'), s.newItems)),
        if (data.popular.isNotEmpty)
          ..._shelf(s.popular, data.popular,
              () => _openCatalog(const ProductQuery(), s.popular)),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ];

  List<Widget> _shelf(
      String title, List<GroceryProduct> products, VoidCallback onAll) {
    final s = GStr.of(context);
    return [
      SliverToBoxAdapter(
          child: _SectionTitle(title, action: s.seeAll, onAction: onAll)),
      SliverToBoxAdapter(
        child: SizedBox(
          // Grows with the system text size so a shelf card never clips its price or control.
          height: 296 +
              170 *
                  (MediaQuery.textScalerOf(context).scale(1) - 1)
                      .clamp(0.0, 1.0),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: products.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) => _ShelfCard(
              product: products[i],
              services: _services,
              onOpen: () => _openProduct(products[i]),
            ),
          ),
        ),
      ),
    ];
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.title,
    required this.subtitle,
    required this.city,
    required this.searchHint,
    required this.onSearch,
  });

  final String title;
  final String subtitle;
  final String city;
  final String searchHint;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(children: [
      Container(
        height: 236,
        decoration: const BoxDecoration(
          gradient: KundePalette.heroGradient,
        ),
        child: ClipRect(
          child: Opacity(
            opacity: .38,
            child: Image.asset('assets/photos/groceries.jpg',
                width: double.infinity,
                height: 236,
                fit: BoxFit.cover,
                alignment: Alignment.centerRight,
                errorBuilder: (_, __, ___) => const SizedBox.shrink()),
          ),
        ),
      ),
      Container(
        height: 236,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              KundePalette.deepViolet.withValues(alpha: .92),
              KundePalette.deepViolet.withValues(alpha: .25),
            ],
          ),
        ),
      ),
      SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                color: Colors.white,
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back),
              ),
              const Spacer(),
            ]),
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -.8)),
                    const SizedBox(height: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 240),
                      child: Text(subtitle,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14, height: 1.3)),
                    ),
                  ]),
            ),
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 196),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.place_outlined, size: 18, color: scheme.primary),
              const SizedBox(width: 4),
              Text(city, style: const TextStyle(fontWeight: FontWeight.w700)),
              Icon(Icons.keyboard_arrow_down, size: 18, color: scheme.primary),
            ]),
            const SizedBox(height: 10),
            Semantics(
              button: true,
              label: searchHint,
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: onSearch,
                child: Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: .6)),
                  ),
                  child: Row(children: [
                    Icon(Icons.search, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(searchHint,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: scheme.onSurfaceVariant)),
                    ),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.items});

  final List<(IconData, String, VoidCallback)> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(children: [
        for (final item in items)
          Expanded(
            child: Semantics(
              button: true,
              label: item.$2,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: item.$3,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(16)),
                      child: Icon(item.$1, color: scheme.primary),
                    ),
                    const SizedBox(height: 6),
                    Text(item.$2,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
        child: Row(children: [
          Expanded(
            child: Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
          ),
          if (action != null)
            TextButton(onPressed: onAction, child: Text(action!)),
        ]),
      );
}

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid(
      {required this.categories, required this.language, required this.onTap});

  final List<GroceryCategory> categories;
  final String language;
  final void Function(GroceryCategory) onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      // A wrapping layout (not a fixed-ratio grid) so tiles grow with the system text size instead of clipping.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tileWidth = constraints.maxWidth / 4;
          return Wrap(
            children: [
              for (final c in categories)
                SizedBox(
                  width: tileWidth,
                  child: Semantics(
                    button: true,
                    label: c.name(language),
                    excludeSemantics: true,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => onTap(c),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Column(children: [
                          Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                                color: scheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(18)),
                            child: Icon(groceryIcon(c.icon),
                                size: 28, color: scheme.primary),
                          ),
                          const SizedBox(height: 6),
                          Text(c.name(language),
                              textAlign: TextAlign.center,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                        ]),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// A compact vertical product card of a horizontal shelf.
class _ShelfCard extends StatelessWidget {
  const _ShelfCard(
      {required this.product, required this.services, required this.onOpen});

  final GroceryProduct product;
  final GroceriesServices services;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = GStr.of(context);
    final sellable = product.inStock && product.storeOpen;
    return SizedBox(
      width: 188,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Stack(children: [
                Center(
                  child: Opacity(
                    opacity: sellable ? 1 : .5,
                    child: EmojiTile(
                        emoji: product.emoji,
                        tone: product.tone,
                        size: 88,
                        radius: 16,
                        imageUrl: product.imageUrl),
                  ),
                ),
                if (product.discountPercent != null)
                  Positioned(
                    left: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: theme.colorScheme.error,
                          borderRadius: BorderRadius.circular(8)),
                      child: Text('-${product.discountPercent}%',
                          style: TextStyle(
                              color: theme.colorScheme.onError,
                              fontSize: 11,
                              fontWeight: FontWeight.w800)),
                    ),
                  ),
              ]),
              const SizedBox(height: 8),
              Text(product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700, height: 1.2)),
              const Spacer(),
              PriceText(product),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: sellable
                    ? AddControl(
                        product: product,
                        services: services,
                        onOpen: onOpen,
                        horizontal: true)
                    : Text(s.outOfStock,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: theme.colorScheme.error)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
