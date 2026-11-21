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
  int _tab = 0;
  Future<FoodReviewSummary>? _reviews;
  Future<List<FoodPromotion>>? _promos;
  bool? _favorite;

  bool get _food => widget.restaurant.vertical == 'FOOD';

  String _tx(String ru, String kk, String en) {
    if (widget.restaurant.vertical != 'FLOWERS_GIFTS') return ru;
    return switch (Localizations.localeOf(context).languageCode) {
      'kk' => kk,
      'en' => en,
      _ => ru,
    };
  }

  @override
  void initState() {
    super.initState();
    _menu = widget.preloaded != null
        ? Future.value(widget.preloaded)
        : widget.services.api.menu(widget.restaurant.id);
    if (_food) {
      _promos = widget.services.api
          .promotions(restaurantId: widget.restaurant.id)
          .catchError((_) => <FoodPromotion>[]);
      widget.services.api.favorites().then((list) {
        if (mounted) {
          setState(
              () => _favorite = list.any((r) => r.id == widget.restaurant.id));
        }
      }).catchError((_) {});
    }
  }

  Future<void> _toggleFavorite() async {
    final current = _favorite;
    if (current == null) return;
    setState(() => _favorite = !current);
    try {
      await widget.services.api.setFavorite(widget.restaurant.id, !current);
    } on FoodException catch (error) {
      if (!mounted) return;
      setState(() => _favorite = current);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
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
          grocery: restaurant.vertical == 'GROCERY',
          flowers: restaurant.vertical == 'FLOWERS_GIFTS'),
    );
    if (added == null || !mounted) return;
    if (cart.conflictsWith(restaurant.id)) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(_tx('Начать новую корзину?', 'Жаңа себет басталсын ба?',
              'Start a new cart?')),
          content: Text(_tx(
              'В корзине блюда из «${cart.restaurant?.name}». Заказать можно только из одного ресторана — корзина будет очищена.',
              'Себетте «${cart.restaurant?.name}» тауарлары бар. Бір дүкеннен ғана тапсырыс беруге болады; себет тазаланады.',
              'Your cart contains items from “${cart.restaurant?.name}”. You can order from one shop at a time; the cart will be cleared.')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(_tx('Отмена', 'Бас тарту', 'Cancel'))),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(_tx(
                    'Очистить и добавить', 'Тазалап қосу', 'Clear and add'))),
          ],
        ),
      );
      if (replace != true || !mounted) return;
    }
    cart.add(restaurant, added);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content:
              Text('${_tx('Добавлено', 'Қосылды', 'Added')}: ${added.name}')));
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
                    actions: [
                      if (_favorite != null)
                        IconButton(
                          key: const Key('restaurant-favorite'),
                          tooltip: _favorite!
                              ? 'Убрать из избранного'
                              : 'В избранное',
                          onPressed: _toggleFavorite,
                          icon: Icon(_favorite!
                              ? Icons.favorite
                              : Icons.favorite_border),
                        ),
                    ],
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
                  if (_food) SliverToBoxAdapter(child: _tabs()),
                  if (_food && _tab == 1)
                    SliverToBoxAdapter(child: _reviewsPanel(restaurant))
                  else if (_food && _tab == 2)
                    SliverToBoxAdapter(child: _about(restaurant))
                  else if (state.connectionState != ConnectionState.done)
                    const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(child: CircularProgressIndicator()))
                  else if (state.hasError)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: FoodStateMessage(
                        icon: Icons.cloud_off_outlined,
                        title: _tx('Не удалось загрузить меню',
                            'Тауарлар жүктелмеді', 'Could not load products'),
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
                              ? _tx('Ассортимент пока пуст',
                                  'Әзірге тауарлар жоқ', 'No products yet')
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
                          flowers: restaurant.vertical == 'FLOWERS_GIFTS',
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
        if (r.ratingAvg != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              const Icon(Icons.star_rounded, color: Color(0xFFF5A623)),
              const SizedBox(width: 4),
              Text(
                  '${r.ratingAvg!.toStringAsFixed(1).replaceAll('.', ',')} · ${r.ratingCount} отзывов',
                  key: const Key('restaurant-rating-line'),
                  style: theme.textTheme.titleSmall),
            ]),
          ),
        Wrap(spacing: 8, runSpacing: 8, children: [
          Chip(
              avatar: const Icon(Icons.schedule_rounded, size: 18),
              label: Text(r.eta)),
          if (r.pickupEnabled && r.vertical == 'FOOD')
            const Chip(
                avatar: Icon(Icons.storefront_outlined, size: 18),
                label: Text('Самовывоз')),
          Chip(
              avatar: const Icon(Icons.delivery_dining_rounded, size: 18),
              label: Text(r.deliveryFeeMinor == 0
                  ? _tx('Доставка бесплатно', 'Жеткізу тегін', 'Free delivery')
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

  Widget _tabs() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(children: [
          FutureBuilder<List<FoodPromotion>>(
            future: _promos,
            builder: (context, state) {
              final promos = state.data ?? const <FoodPromotion>[];
              if (promos.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final p in promos)
                    Chip(
                      key: const Key('restaurant-promo'),
                      avatar: const Icon(Icons.local_offer_outlined, size: 18),
                      label: Text(p.code == null
                          ? '${p.title} ${p.valueLabel}'
                          : '${p.valueLabel} · код ${p.code}'),
                    ),
                ]),
              );
            },
          ),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              key: const Key('restaurant-tabs'),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 0, label: Text('Меню')),
                ButtonSegment(value: 1, label: Text('Отзывы')),
                ButtonSegment(value: 2, label: Text('О заведении')),
              ],
              selected: {_tab},
              onSelectionChanged: (v) => setState(() {
                _tab = v.first;
                if (_tab == 1) {
                  _reviews ??=
                      widget.services.api.reviews(widget.restaurant.id);
                }
              }),
            ),
          ),
        ]),
      );

  Widget _reviewsPanel(Restaurant r) => FutureBuilder<FoodReviewSummary>(
        future: _reviews,
        builder: (context, state) {
          if (state.connectionState != ConnectionState.done) {
            return const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()));
          }
          if (state.hasError) {
            return FoodStateMessage(
                icon: Icons.cloud_off_outlined,
                title: 'Не удалось загрузить отзывы',
                onAction: () => setState(() => _reviews =
                    widget.services.api.reviews(widget.restaurant.id)));
          }
          final summary = state.data!;
          final theme = Theme.of(context);
          if (summary.count == 0) {
            return const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                  child: Text(
                      'Отзывов пока нет. Оставить отзыв можно после доставленного заказа.',
                      textAlign: TextAlign.center)),
            );
          }
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(summary.average!.toStringAsFixed(1).replaceAll('.', ','),
                    style: theme.textTheme.displaySmall),
                const SizedBox(width: 8),
                Text('${summary.count} отзывов',
                    style: theme.textTheme.bodyLarge),
              ]),
              const SizedBox(height: 12),
              for (final review in summary.reviews)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Row(children: [
                      for (var i = 1; i <= 5; i++)
                        Icon(
                            i <= review.rating
                                ? Icons.star_rounded
                                : Icons.star_border_rounded,
                            size: 18,
                            color: const Color(0xFFF5A623)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(review.author,
                              overflow: TextOverflow.ellipsis)),
                    ]),
                    subtitle:
                        review.comment == null ? null : Text(review.comment!),
                    trailing: IconButton(
                      tooltip: 'Пожаловаться на отзыв',
                      icon: const Icon(Icons.flag_outlined),
                      onPressed: () => _complain(review),
                    ),
                  ),
                ),
            ]),
          );
        },
      );

  Future<void> _complain(FoodReview review) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.services.api
          .complainAboutReview(review.id, 'Отзыв нарушает правила');
      messenger.showSnackBar(const SnackBar(
          content: Text('Жалоба отправлена. Спасибо за обращение.')));
    } on FoodException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Widget _about(Restaurant r) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.place_outlined),
          title: Text(r.addressText ?? 'Адрес не указан'),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.delivery_dining_rounded),
          title: Text(r.deliveryFeeMinor == 0
              ? 'Доставка бесплатно'
              : 'Доставка ${formatTenge(r.deliveryFeeMinor)}'),
          subtitle: Text('Ориентировочно ${r.eta}'),
        ),
        if (r.pickupEnabled)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.storefront_outlined),
            title: const Text('Самовывоз'),
            subtitle: Text('Готовность заказа около ${r.prepMinutes} мин'),
          ),
        if (r.minOrderMinor > 0)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.shopping_basket_outlined),
            title: Text('Минимальный заказ ${formatTenge(r.minOrderMinor)}'),
          ),
        const SizedBox(height: 8),
        Text(r.description, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        Text(
            'Часы работы не публикуются: ресторан открывает и закрывает приём заказов сам.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
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
                  label: Text(_tx('В наличии', 'Қолда бар', 'In stock')),
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
      {required this.dish,
      required this.enabled,
      required this.flowers,
      required this.onTap});

  final Dish dish;
  final bool enabled;
  final bool flowers;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canOrder = enabled && dish.available;
    final unavailable = flowers
        ? switch (Localizations.localeOf(context).languageCode) {
            'kk' => 'Қолжетімсіз',
            'en' => 'Unavailable',
            _ => 'Нет в наличии',
          }
        : 'Нет в наличии';
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
                              : unavailable,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                    ]),
              ),
              const SizedBox(width: 12),
              Stack(clipBehavior: Clip.none, children: [
                EmojiTile(
                    emoji: dish.emoji,
                    tone: dish.tone,
                    size: 84,
                    radius: 18,
                    imageUrl: dish.imageUrl),
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
