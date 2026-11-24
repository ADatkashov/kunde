import 'dart:async';

import 'package:flutter/material.dart';

import 'package:kunde_models/food_models.dart';
import '../../food/presentation/food_widgets.dart';
import '../data/groceries_api.dart';
import '../data/groceries_models.dart';
import '../data/groceries_services.dart';
import 'grocery_widgets.dart';
import 'groceries_strings.dart';
import 'product_screen.dart';

/// Product catalog. Search (debounced), filters, sorting and paging are all executed by the server; this screen only
/// holds the query and the pages loaded so far. Returning from a product keeps the query, the loaded pages and the
/// scroll position because the screen stays on the navigator stack.
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({
    required this.services,
    required this.initial,
    required this.title,
    this.autofocusSearch = false,
    this.debounce = const Duration(milliseconds: 400),
    super.key,
  });

  final GroceriesServices services;
  final ProductQuery initial;
  final String title;
  final bool autofocusSearch;
  final Duration debounce;

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  static const _pageSize = 30;

  late ProductQuery _query = widget.initial;
  final _items = <GroceryProduct>[];
  final _scroll = ScrollController();
  late final TextEditingController _search =
      TextEditingController(text: widget.initial.q);
  Timer? _timer;
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;
  int _generation = 0;

  GroceriesServices get _services => widget.services;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 400) _loadMore();
    });
    _services.loadFavorites();
    _reload();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _items.clear();
    });
    try {
      final page = await _services.api.products(_query, limit: _pageSize);
      if (!mounted || generation != _generation) return;
      setState(() {
        _items.addAll(page.items);
        _total = page.total;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || _error != null || _items.length >= _total) {
      return;
    }
    final generation = _generation;
    setState(() => _loadingMore = true);
    try {
      final page = await _services.api
          .products(_query, limit: _pageSize, offset: _items.length);
      if (!mounted || generation != _generation) return;
      setState(() {
        _items.addAll(page.items);
        _total = page.total;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loadingMore = false;
        _error = error;
      });
    }
  }

  void _apply(ProductQuery query) {
    _query = query;
    _reload();
  }

  void _onSearchChanged(String text) {
    _timer?.cancel();
    _timer = Timer(widget.debounce, () {
      if (text.trim() != _query.q.trim()) _apply(_query.copyWith(q: text));
    });
  }

  void _open(GroceryProduct product) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) =>
            ProductScreen(services: _services, productId: product.id),
      ));

  Future<void> _filters() async {
    final result = await showModalBottomSheet<ProductQuery>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FiltersSheet(services: _services, query: _query),
    );
    if (result != null) _apply(result);
  }

  @override
  Widget build(BuildContext context) {
    final s = GStr.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _search,
              autofocus: widget.autofocusSearch,
              textInputAction: TextInputAction.search,
              onChanged: _onSearchChanged,
              onSubmitted: (text) {
                _timer?.cancel();
                _apply(_query.copyWith(q: text));
              },
              decoration: InputDecoration(
                hintText: s.searchHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: s.reset,
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _search.clear();
                          _apply(_query.copyWith(q: ''));
                        },
                      ),
                isDense: true,
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: FoodCartBar(services: _services.food),
      body: Column(children: [
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              _chip(
                label: _query.activeFilters == 0
                    ? s.filters
                    : '${s.filters} · ${_query.activeFilters}',
                icon: Icons.tune,
                selected: _query.activeFilters > 0,
                onTap: _filters,
              ),
              _chip(
                label: s.inStock,
                selected: _query.inStock,
                onTap: () => _apply(_query.copyWith(inStock: !_query.inStock)),
              ),
              _chip(
                label: s.onSale,
                selected: _query.onSale,
                onTap: () => _apply(_query.copyWith(onSale: !_query.onSale)),
              ),
              _chip(
                label: s.newOnly,
                selected: _query.newOnly,
                onTap: () => _apply(_query.copyWith(newOnly: !_query.newOnly)),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
          child: Row(children: [
            Expanded(
              child: Text(_loading ? '' : s.productsCount(_total),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ),
            Flexible(
              child: PopupMenuButton<String>(
                tooltip: s.sortLabel,
                initialValue: _query.sort,
                onSelected: (sort) => _apply(_query.copyWith(sort: sort)),
                itemBuilder: (_) => [
                  for (final sort in const [
                    'popularity',
                    'price_asc',
                    'price_desc',
                    'new',
                    'discount'
                  ])
                    PopupMenuItem(value: sort, child: Text(s.sortName(sort))),
                ],
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.swap_vert, size: 18, color: scheme.primary),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(s.sortName(_query.sort),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: scheme.primary,
                                fontWeight: FontWeight.w700)),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ]),
        ),
        Expanded(child: _body(s)),
      ]),
    );
  }

  Widget _chip(
          {required String label,
          required bool selected,
          required VoidCallback onTap,
          IconData? icon}) =>
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child:
            _Pill(label: label, selected: selected, icon: icon, onTap: onTap),
      );

  Widget _body(GStr s) {
    if (_loading) {
      return const SingleChildScrollView(child: ProductListSkeleton());
    }
    if (_error != null && _items.isEmpty) {
      final error = _error!;
      return GroceryMessage(
        icon: Icons.cloud_off_outlined,
        title: error is GroceriesException
            ? error.messageFor(s.language)
            : s.retry,
        actionLabel: s.retry,
        onAction: _reload,
      );
    }
    if (_items.isEmpty) {
      return GroceryMessage(
        icon: Icons.search_off,
        title: s.nothingFound,
        body: s.nothingFoundHint,
        actionLabel:
            _query.activeFilters > 0 || _query.q.isNotEmpty ? s.reset : null,
        onAction: () {
          _search.clear();
          _apply(const ProductQuery());
        },
      );
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _items.length + 1,
        itemBuilder: (context, i) {
          if (i < _items.length) {
            final product = _items[i];
            return ProductRow(
                product: product,
                services: _services,
                onOpen: () => _open(product));
          }
          if (_loadingMore) {
            return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()));
          }
          if (_error != null) {
            return Padding(
              padding: const EdgeInsets.all(8),
              child: TextButton(
                  onPressed: () {
                    setState(() => _error = null);
                    _loadMore();
                  },
                  child: Text(s.retry)),
            );
          }
          return const SizedBox(height: 24);
        },
      ),
    );
  }
}

/// A 48 dp high toggle pill (filter / sort chip) with a proper button role for screen readers.
class _Pill extends StatelessWidget {
  const _Pill(
      {required this.label,
      required this.selected,
      required this.onTap,
      this.icon});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? scheme.primaryContainer : scheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: selected ? scheme.primary : scheme.outlineVariant),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[
                  Icon(icon, size: 18),
                  const SizedBox(width: 6),
                ],
                Text(label,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? scheme.onPrimaryContainer
                            : scheme.onSurface)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet with the store, brand and price filters. Returns the updated query, or null when dismissed.
class _FiltersSheet extends StatefulWidget {
  const _FiltersSheet({required this.services, required this.query});

  final GroceriesServices services;
  final ProductQuery query;

  @override
  State<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<_FiltersSheet> {
  late ProductQuery _query = widget.query;
  late final _from =
      TextEditingController(text: _tenge(widget.query.minPriceMinor));
  late final _to =
      TextEditingController(text: _tenge(widget.query.maxPriceMinor));
  List<Restaurant> _stores = const [];
  List<String> _brands = const [];

  static String _tenge(int? minor) => minor == null ? '' : '${minor ~/ 100}';

  @override
  void initState() {
    super.initState();
    widget.services.stores().then((v) {
      if (mounted) setState(() => _stores = v);
    }).catchError((_) {});
    widget.services.api
        .brands(category: widget.query.category, storeId: widget.query.storeId)
        .then((v) {
      if (mounted) setState(() => _brands = v);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  int? _minor(String text) {
    final value = int.tryParse(text.trim());
    return value == null || value < 0 ? null : value * 100;
  }

  @override
  Widget build(BuildContext context) {
    final s = GStr.of(context);
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.filters,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          Text(s.store, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final store in _stores)
              ChoiceChip(
                label: Text(store.name),
                selected: _query.storeId == store.id,
                onSelected: (on) => setState(() =>
                    _query = _query.copyWith(storeId: on ? store.id : null)),
              ),
          ]),
          if (_brands.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(s.brand, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final brand in _brands)
                ChoiceChip(
                  label: Text(brand),
                  selected: _query.brand == brand,
                  onSelected: (on) => setState(
                      () => _query = _query.copyWith(brand: on ? brand : null)),
                ),
            ]),
          ],
          const SizedBox(height: 14),
          Text(s.price, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _from,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: s.priceFrom),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _to,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: s.priceTo),
              ),
            ),
          ]),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(
                    context,
                    ProductQuery(
                        q: _query.q,
                        sort: _query.sort,
                        category: _query.category)),
                child: Text(s.reset),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: () => Navigator.pop(
                    context,
                    _query.copyWith(
                        minPriceMinor: _minor(_from.text),
                        maxPriceMinor: _minor(_to.text))),
                child: Text(s.apply),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
