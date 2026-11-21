import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../food/data/food_models.dart';
import '../../food/presentation/food_widgets.dart';
import '../data/groceries_api.dart';
import '../data/groceries_models.dart';
import '../data/groceries_services.dart';
import 'grocery_widgets.dart';
import 'groceries_strings.dart';
import 'lists_screen.dart';

/// Product page: photo, name, badges, price per unit, quantity (grams in 100 g steps for weighed goods), description,
/// composition, nutrition, storage and origin, availability, related products, favorite, share and add-to-cart.
/// Price and availability come from the server on every open; the cart only holds a preview.
class ProductScreen extends StatefulWidget {
  const ProductScreen(
      {required this.services, required this.productId, super.key});

  final GroceriesServices services;
  final String productId;

  @override
  State<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends State<ProductScreen> {
  late Future<ProductDetail> _future;
  final Map<String, Set<String>> _selected = {};
  int? _quantity;
  bool _optionsReady = false;

  GroceriesServices get _services => widget.services;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _services.loadFavorites();
  }

  Future<ProductDetail> _load() => _services.api.product(widget.productId);

  void _reload() => setState(() {
        _optionsReady = false;
        _future = _load();
      });

  void _prepare(ProductDetail detail) {
    if (_optionsReady) return;
    _optionsReady = true;
    _quantity ??= detail.product.defaultQuantity;
    for (final group in detail.optionGroups) {
      _selected[group.id] =
          group.single && group.required && group.options.isNotEmpty
              ? {group.options.first.id}
              : <String>{};
    }
  }

  List<DishOption> _chosen(ProductDetail detail) => [
        for (final group in detail.optionGroups)
          for (final option in group.options)
            if (_selected[group.id]?.contains(option.id) ?? false) option,
      ];

  bool _valid(ProductDetail detail) => detail.optionGroups.every((g) {
        final n = _selected[g.id]?.length ?? 0;
        return n >= g.minSelect && n <= g.maxSelect;
      });

  /// Opens the system share sheet. Where no share target exists the text is shown in a dialog instead of failing silently.
  Future<void> _share(ProductDetail detail) async {
    final s = GStr.of(context);
    final p = detail.product;
    final text =
        '${p.name} — ${unitPriceLabel(p.unit, p.priceMinor)} · ${p.storeName} · KUNDE';
    final messenger = ScaffoldMessenger.of(context);
    try {
      await SharePlus.instance.share(ShareParams(text: text, subject: p.name));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(s.retry)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = GStr.of(context);
    return Scaffold(
      bottomNavigationBar: FoodCartBar(services: _services.food),
      body: FutureBuilder<ProductDetail>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Column(children: [
              AppBar(),
              const Padding(
                padding: EdgeInsets.all(16),
                child: Column(children: [
                  SkeletonBox(height: 260, radius: 24),
                  SizedBox(height: 16),
                  SkeletonBox(height: 28),
                  SizedBox(height: 10),
                  SkeletonBox(height: 20, width: 140),
                ]),
              ),
            ]);
          }
          if (snapshot.hasError) {
            final error = snapshot.error;
            return Column(children: [
              AppBar(),
              Expanded(
                child: GroceryMessage(
                  icon: Icons.cloud_off_outlined,
                  title: error is GroceriesException
                      ? error.messageFor(s.language)
                      : s.retry,
                  actionLabel: s.retry,
                  onAction: _reload,
                ),
              ),
            ]);
          }
          final detail = snapshot.data!;
          _prepare(detail);
          return _content(detail, s);
        },
      ),
    );
  }

  Widget _content(ProductDetail detail, GStr s) {
    final theme = Theme.of(context);
    final p = detail.product;
    final sellable = p.inStock && p.storeOpen;
    final delta =
        _chosen(detail).fold<int>(0, (sum, o) => sum + o.priceDeltaMinor);
    final quantity = (_quantity ?? p.defaultQuantity)
        .clamp(detail.minQuantity, p.maxQuantity < 1 ? 1 : p.maxQuantity);
    final total = lineTotalMinor(p.unit, p.priceMinor + delta, quantity);
    return Column(children: [
      Expanded(
        child: CustomScrollView(slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 300,
            backgroundColor: theme.scaffoldBackgroundColor,
            actions: [
              IconButton(
                tooltip: s.share,
                icon: const Icon(Icons.ios_share),
                onPressed: () => _share(detail),
              ),
              FavoriteButton(services: _services, productId: p.id),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Padding(
                padding: const EdgeInsets.fromLTRB(40, 72, 40, 16),
                child: _Gallery(product: p, images: detail.images),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name,
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(
                      [if (p.brand != null) p.brand!, p.storeName].join(' · '),
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 6, children: [
                      if (p.discountPercent != null)
                        _Tag(
                            '-${p.discountPercent}%',
                            theme.colorScheme.errorContainer,
                            theme.colorScheme.onErrorContainer),
                      if (p.isNew)
                        _Tag(s.newBadge, theme.colorScheme.primaryContainer,
                            theme.colorScheme.onPrimaryContainer),
                      if (detail.originCountry != null)
                        _Tag(
                            detail.originCountry!,
                            theme.colorScheme.surfaceContainerHigh,
                            theme.colorScheme.onSurface),
                      _Tag(
                          sellable
                              ? s.inStock
                              : (p.inStock ? s.storeClosed : s.outOfStock),
                          sellable
                              ? theme.colorScheme.secondaryContainer
                              : theme.colorScheme.errorContainer,
                          sellable
                              ? theme.colorScheme.onSecondaryContainer
                              : theme.colorScheme.onErrorContainer),
                    ]),
                    const SizedBox(height: 14),
                    PriceText(p, large: true),
                    const SizedBox(height: 16),
                    if (sellable)
                      _Stepper(
                        label: s.quantity,
                        value: formatQuantity(p.unit, quantity),
                        onMinus: quantity <= detail.minQuantity
                            ? null
                            : () => setState(() =>
                                _quantity = quantity - detail.quantityStep),
                        onPlus: quantity >= p.maxQuantity
                            ? null
                            : () => setState(() =>
                                _quantity = quantity + detail.quantityStep),
                      ),
                    if (p.weighed)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(s.weighedNote,
                            style: theme.textTheme.bodySmall),
                      ),
                    for (final group in detail.optionGroups)
                      _optionGroup(group, s),
                    if (p.description.isNotEmpty)
                      _Block(s.description, Text(p.description)),
                    if (detail.composition != null)
                      _Block(s.composition, Text(detail.composition!)),
                    if (detail.nutrition != null)
                      _Block(s.nutrition, _NutritionRow(detail.nutrition!, s)),
                    if (detail.storageConditions != null)
                      _Block(s.storage, Text(detail.storageConditions!)),
                    if (detail.originCountry != null)
                      _Block(s.origin, Text(detail.originCountry!)),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () =>
                          showAddToListSheet(context, _services, p),
                      icon: const Icon(Icons.playlist_add),
                      label: Text(s.addToList),
                    ),
                  ]),
            ),
          ),
          if (detail.related.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                child: Text(s.related,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ),
            ),
            SliverList.builder(
              itemCount: detail.related.length,
              itemBuilder: (context, i) => ProductRow(
                product: detail.related[i],
                services: _services,
                onOpen: () =>
                    Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => ProductScreen(
                      services: _services, productId: detail.related[i].id),
                )),
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ]),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
            onPressed: sellable && _valid(detail)
                ? () async {
                    final chosen = _chosen(detail);
                    final added = await addProductToCart(
                      context,
                      _services,
                      p,
                      quantity: quantity,
                      optionIds: [for (final o in chosen) o.id],
                      optionsText: chosen.map((o) => o.name).join(', '),
                      optionsDeltaMinor: delta,
                    );
                    if (added && mounted) Navigator.of(context).maybePop();
                  }
                : null,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Flexible(
                child: Text(
                    sellable
                        ? s.addToCart
                        : (p.inStock ? s.storeClosed : s.outOfStock),
                    overflow: TextOverflow.ellipsis),
              ),
              if (sellable) ...[
                const SizedBox(width: 12),
                Text(formatTenge(total),
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ],
            ]),
          ),
        ),
      ),
    ]);
  }

  Widget _optionGroup(OptionGroup group, GStr s) {
    final selected = _selected[group.id] ?? <String>{};
    return _Block(
      group.required ? '${group.name} · ${s.requiredLabel}' : group.name,
      Wrap(spacing: 8, runSpacing: 4, children: [
        for (final option in group.options)
          ChoiceChip(
            label: Text(option.priceDeltaMinor == 0
                ? option.name
                : '${option.name} +${formatTenge(option.priceDeltaMinor)}'),
            selected: selected.contains(option.id),
            onSelected: (on) => setState(() {
              final next = {...selected};
              if (group.single) {
                next
                  ..clear()
                  ..addAll(on || group.required ? {option.id} : <String>{});
              } else if (on) {
                if (next.length < group.maxSelect) next.add(option.id);
              } else {
                next.remove(option.id);
              }
              _selected[group.id] = next;
            }),
          ),
      ]),
    );
  }
}

/// Photo gallery: swipe between the store's photos with a page indicator and counter. Without a photo the product
/// tile (licensed illustration or emoji) is shown, so a missing or failing image never breaks the layout.
class _Gallery extends StatefulWidget {
  const _Gallery({required this.product, required this.images});

  final GroceryProduct product;
  final List<String> images;

  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final images = widget.images.isNotEmpty
        ? widget.images
        : [if (product.imageUrl != null) product.imageUrl!];
    Widget tile(String? url) => Center(
          child: EmojiTile(
              emoji: product.emoji,
              tone: product.tone,
              size: 220,
              radius: 28,
              imageUrl: url),
        );
    if (images.length <= 1) return tile(images.firstOrNull);
    return Column(children: [
      Expanded(
        child: PageView(
          key: const Key('product-gallery'),
          onPageChanged: (i) => setState(() => _page = i),
          children: [for (final url in images) tile(url)],
        ),
      ),
      const SizedBox(height: 6),
      Semantics(
        label: '${_page + 1}/${images.length}',
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < images.length; i++)
            Container(
              width: i == _page ? 18 : 7,
              height: 7,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                  color: i == _page
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(4)),
            ),
        ]),
      ),
    ]);
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, this.background, this.foreground);

  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: background, borderRadius: BorderRadius.circular(10)),
        child: Text(text,
            style: TextStyle(
                color: foreground, fontSize: 12, fontWeight: FontWeight.w700)),
      );
}

class _Block extends StatelessWidget {
  const _Block(this.title, this.child);

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          child,
        ]),
      );
}

class _NutritionRow extends StatelessWidget {
  const _NutritionRow(this.nutrition, this.s);

  final Nutrition nutrition;
  final GStr s;

  String _n(double? v) =>
      v == null ? '—' : v.toStringAsFixed(1).replaceAll('.', ',');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget cell(String label, String value) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(14)),
            child: Column(children: [
              Text(value,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 2),
              Text(label, style: Theme.of(context).textTheme.labelSmall),
            ]),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(s.per100, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 6),
      Row(children: [
        cell(s.kcal, nutrition.kcal?.toString() ?? '—'),
        const SizedBox(width: 8),
        cell(s.protein, _n(nutrition.protein)),
        const SizedBox(width: 8),
        cell(s.fat, _n(nutrition.fat)),
        const SizedBox(width: 8),
        cell(s.carbs, _n(nutrition.carbs)),
      ]),
    ]);
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper(
      {required this.label,
      required this.value,
      required this.onMinus,
      required this.onPlus});

  final String label;
  final String value;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: Text(label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall),
        ),
        IconButton.outlined(
            tooltip: '−', onPressed: onMinus, icon: const Icon(Icons.remove)),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 64, maxWidth: 96),
          child: Semantics(
            liveRegion: true,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 17)),
            ),
          ),
        ),
        IconButton.filled(
            tooltip: '+', onPressed: onPlus, icon: const Icon(Icons.add)),
      ]);
}
