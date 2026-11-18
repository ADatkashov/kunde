import 'package:flutter/material.dart';

import '../data/cart_controller.dart';
import '../data/food_api.dart';
import '../data/food_models.dart';
import '../food_services.dart';
import 'dish_sheet.dart';
import 'food_widgets.dart';

/// Restaurant page: header, menu sections and dish cards. Tapping a dish opens the option sheet.
class RestaurantScreen extends StatefulWidget {
  const RestaurantScreen(
      {required this.services,
      required this.restaurant,
      this.preloaded,
      super.key});

  final FoodServices services;
  final Restaurant restaurant;
  final RestaurantMenu? preloaded;

  @override
  State<RestaurantScreen> createState() => _RestaurantScreenState();
}

class _RestaurantScreenState extends State<RestaurantScreen> {
  late Future<RestaurantMenu> _menu;
  final _sectionKeys = <String, GlobalKey>{};
  bool _inStockOnly = false;

  @override
  void initState() {
    super.initState();
    _menu = widget.preloaded != null
        ? Future.value(widget.preloaded)
        : widget.services.api.menu(widget.restaurant.id);
  }

  Future<void> _openDish(Restaurant restaurant, Dish dish) async {
    final cart = widget.services.cart;
    final added = await showModalBottomSheet<CartLine>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => DishSheet(
          dish: dish,
          restaurantOpen: restaurant.open,
          api: widget.services.api,
          grocery: restaurant.vertical != 'FOOD'),
    );
    if (added == null || !mounted) return;
    if (cart.conflictsWith(restaurant.id)) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Начать новую корзину?'),
          content: Text('В корзине блюда из «${cart.restaurant?.name}». '
              'Заказать можно только из одного ресторана — корзина будет очищена.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Отмена')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Очистить и добавить')),
          ],
        ),
      );
      if (replace != true || !mounted) return;
    }
    cart.add(restaurant, added);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Добавлено: ${added.name}')));
  }

  void _scrollTo(String sectionId) {
    final context = _sectionKeys[sectionId]?.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(context,
          duration: const Duration(milliseconds: 300), alignment: 0.02);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        bottomNavigationBar: FoodCartBar(services: widget.services),
        body: FutureBuilder<RestaurantMenu>(
          future: _menu,
          builder: (context, state) {
            final restaurant = state.data?.restaurant ?? widget.restaurant;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: CustomScrollView(slivers: [
                  SliverAppBar(
                    pinned: true,
                    expandedHeight: 168,
                    title: Text(restaurant.name),
                    flexibleSpace: FlexibleSpaceBar(
                      background: Container(
                        color: toneColors(restaurant.tone).background,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.only(top: 40),
                        child: EmojiTile(
                            emoji: restaurant.emoji,
                            tone: restaurant.tone,
                            size: 112,
                            radius: 28),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(child: _info(context, restaurant)),
                  if (state.connectionState != ConnectionState.done)
                    const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(child: CircularProgressIndicator()))
                  else if (state.hasError)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: FoodStateMessage(
                        icon: Icons.cloud_off_outlined,
                        title: 'Не удалось загрузить меню',
                        body: state.error is FoodException
                            ? (state.error as FoodException).message
                            : null,
                        onAction: () => setState(() {
                          _menu =
                              widget.services.api.menu(widget.restaurant.id);
                        }),
                      ),
                    )
                  else if (state.data!.sections.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: FoodStateMessage(
                          icon: Icons.menu_book_outlined,
                          title: restaurant.vertical != 'FOOD'
                              ? 'Ассортимент пока пуст'
                              : 'Меню пока пустое'),
                    )
                  else ...[
                    SliverToBoxAdapter(child: _chips(state.data!.sections)),
                    for (final section in _visible(state.data!.sections)) ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          key: _sectionKeys.putIfAbsent(
                              section.id, GlobalKey.new),
                          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                          child: Text(section.name,
                              style: Theme.of(context).textTheme.headlineSmall),
                        ),
                      ),
                      SliverList.builder(
                        itemCount: section.dishes.length,
                        itemBuilder: (context, i) => _DishTile(
                          dish: section.dishes[i],
                          enabled: restaurant.open,
                          onTap: () => _openDish(restaurant, section.dishes[i]),
                        ),
                      ),
                    ],
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  ],
                ]),
              ),
            );
          },
        ),
      );

  Widget _info(BuildContext context, Restaurant r) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(r.cuisine, style: theme.textTheme.titleMedium)),
          if (r.synthetic) const DemoBadge(),
        ]),
        const SizedBox(height: 6),
        Text(r.description,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          Chip(
              avatar: const Icon(Icons.schedule_rounded, size: 18),
              label: Text(r.eta)),
          Chip(
              avatar: const Icon(Icons.delivery_dining_rounded, size: 18),
              label: Text(r.deliveryFeeMinor == 0
                  ? 'Доставка бесплатно'
                  : 'Доставка ${formatTenge(r.deliveryFeeMinor)}')),
          if (r.minOrderMinor > 0)
            Chip(
                avatar: const Icon(Icons.shopping_basket_outlined, size: 18),
                label: Text('Минимум ${formatTenge(r.minOrderMinor)}')),
        ]),
        if (!r.open)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Material(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(r.vertical != 'FOOD'
                    ? 'Магазин сейчас закрыт — заказ недоступен.'
                    : 'Ресторан сейчас закрыт — заказ недоступен.'),
              ),
            ),
          ),
      ]),
    );
  }

  /// Sections with only products that can be ordered when the in-stock filter is on.
  List<MenuSection> _visible(List<MenuSection> sections) => !_inStockOnly
      ? sections
      : [
          for (final s in sections)
            if (s.dishes.any((d) => d.available && d.maxQuantity > 0))
              MenuSection(id: s.id, name: s.name, dishes: [
                for (final d in s.dishes)
                  if (d.available && d.maxQuantity > 0) d
              ]),
        ];

  Widget _chips(List<MenuSection> sections) => SizedBox(
        height: 56,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          itemCount: sections.length + 1,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) => i == 0
              ? FilterChip(
                  label: const Text('В наличии'),
                  selected: _inStockOnly,
                  onSelected: (v) => setState(() => _inStockOnly = v))
              : ActionChip(
                  label: Text(sections[i - 1].name),
                  onPressed: () => _scrollTo(sections[i - 1].id)),
        ),
      );
}

class _DishTile extends StatelessWidget {
  const _DishTile(
      {required this.dish, required this.enabled, required this.onTap});

  final Dish dish;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canOrder = enabled && dish.available;
    return Semantics(
      button: canOrder,
      label:
          '${dish.name}, ${unitPriceLabel(dish.unit, dish.priceMinor)}${dish.available ? '' : ', нет в наличии'}',
      child: InkWell(
        onTap: canOrder ? onTap : null,
        child: Opacity(
          opacity: dish.available ? 1 : 0.5,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(dish.name, style: theme.textTheme.titleMedium),
                      if (dish.description.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(dish.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
                      ],
                      const SizedBox(height: 8),
                      Text(
                          dish.available && dish.maxQuantity > 0
                              ? unitPriceLabel(dish.unit, dish.priceMinor)
                              : 'Нет в наличии',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                    ]),
              ),
              const SizedBox(width: 12),
              Stack(clipBehavior: Clip.none, children: [
                EmojiTile(
                    emoji: dish.emoji, tone: dish.tone, size: 84, radius: 18),
                if (canOrder)
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          shape: BoxShape.circle),
                      child: Icon(Icons.add_rounded,
                          color: theme.colorScheme.onPrimary, size: 20),
                    ),
                  ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
