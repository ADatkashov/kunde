import 'package:flutter/material.dart';

import '../data/cart_controller.dart';
import '../data/food_api.dart';
import 'package:kunde_models/food_models.dart';
import 'food_widgets.dart';

/// Product card: description, option groups, quantity (pieces, or grams for weighed goods), stock hint and, in
/// stores, the customer's substitution choice. Pops a [CartLine] when the customer adds the product.
class DishSheet extends StatefulWidget {
  const DishSheet({
    required this.dish,
    required this.restaurantOpen,
    this.api,
    this.grocery = false,
    this.flowers = false,
    super.key,
  });

  final Dish dish;
  final bool restaurantOpen;

  /// Used to load acceptable replacements in stores.
  final FoodApi? api;
  final bool grocery;
  final bool flowers;

  @override
  State<DishSheet> createState() => _DishSheetState();
}

class _DishSheetState extends State<DishSheet> {
  final Map<String, Set<String>> _selected = {};
  late int _quantity;
  String _substitution = 'NONE';
  final Set<String> _chosen = {};
  Future<List<DishHit>>? _alternatives;

  Dish get _dish => widget.dish;
  int get _step => _dish.weighed ? 100 : 1;
  int get _max => _dish.maxQuantity;

  @override
  void initState() {
    super.initState();
    _quantity = _dish.weighed ? (_max >= 500 ? 500 : _max) : 1;
    for (final group in _dish.optionGroups) {
      // A required single choice starts on its first option so the price is always valid.
      _selected[group.id] =
          group.single && group.required && group.options.isNotEmpty
              ? {group.options.first.id}
              : <String>{};
    }
    if (widget.grocery && widget.api != null) {
      _alternatives = widget.api!.alternatives(_dish.id);
    }
  }

  List<DishOption> get _chosenOptions => [
        for (final group in _dish.optionGroups)
          for (final option in group.options)
            if (_selected[group.id]!.contains(option.id)) option,
      ];

  int get _unit =>
      _dish.priceMinor +
      _chosenOptions.fold(0, (sum, o) => sum + o.priceDeltaMinor);

  bool get _valid =>
      _max >= _step &&
      _dish.optionGroups.every((g) {
        final count = _selected[g.id]!.length;
        return count >= g.minSelect && count <= g.maxSelect;
      }) &&
      (_substitution != 'CHOSEN' || _chosen.isNotEmpty);

  String _hint(OptionGroup g) {
    if (g.single && g.required) return 'Выберите 1';
    if (g.single) return 'Необязательно';
    if (g.minSelect > 0) return 'Выберите от ${g.minSelect} до ${g.maxSelect}';
    return 'До ${g.maxSelect}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String tx(String ru, String kk, String en) {
      if (!widget.flowers) return ru;
      return switch (Localizations.localeOf(context).languageCode) {
        'kk' => kk,
        'en' => en,
        _ => ru,
      };
    }

    final dish = _dish;
    final lowStock =
        dish.stockQty != null && dish.stockQty! <= (dish.weighed ? 2000 : 5);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(children: [
        Expanded(
          child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              children: [
                if (widget.flowers)
                  _FlowerHero(dish: dish)
                else
                  Center(
                      child: EmojiTile(
                          emoji: dish.emoji,
                          tone: dish.tone,
                          size: 132,
                          radius: 28,
                          imageUrl: dish.imageUrl)),
                const SizedBox(height: 16),
                Text(dish.name, style: theme.textTheme.headlineSmall),
                if (dish.description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(dish.description,
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ],
                const SizedBox(height: 8),
                if (widget.flowers)
                  Row(children: [
                    Expanded(
                        child: Text(unitPriceLabel(dish.unit, dish.priceMinor),
                            style: theme.textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800))),
                    _stepper(tx, theme, dish),
                  ])
                else
                  Text(unitPriceLabel(dish.unit, dish.priceMinor),
                      style: theme.textTheme.titleLarge),
                if (lowStock)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                        '${tx('Осталось', 'Қалды', 'Remaining')}: ${formatQuantity(dish.unit, dish.stockQty!)}',
                        style: TextStyle(
                            color: theme.colorScheme.error,
                            fontWeight: FontWeight.w600)),
                  ),
                if (_max < _step)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                        tx('Нет в наличии', 'Қолжетімсіз', 'Unavailable'),
                        style: TextStyle(color: theme.colorScheme.error)),
                  ),
                for (final group in dish.optionGroups) ...[
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(
                        child: Text(group.name,
                            style: theme.textTheme.titleMedium)),
                    Text(_hint(group), style: theme.textTheme.bodySmall),
                  ]),
                  if (group.single)
                    RadioGroup<String>(
                      groupValue: _selected[group.id]!.isEmpty
                          ? null
                          : _selected[group.id]!.first,
                      onChanged: (value) => setState(() {
                        _selected[group.id] = {if (value != null) value};
                      }),
                      child: Column(children: [
                        for (final option in group.options)
                          RadioListTile<String>(
                            contentPadding: EdgeInsets.zero,
                            value: option.id,
                            title: Text(option.name),
                            secondary: option.priceDeltaMinor == 0
                                ? null
                                : Text(
                                    '+${formatTenge(option.priceDeltaMinor)}'),
                          ),
                      ]),
                    )
                  else
                    for (final option in group.options)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _selected[group.id]!.contains(option.id),
                        title: Text(option.name),
                        secondary: option.priceDeltaMinor == 0
                            ? null
                            : Text('+${formatTenge(option.priceDeltaMinor)}'),
                        onChanged: (on) => setState(() {
                          final set = _selected[group.id]!;
                          if (on == true) {
                            if (set.length < group.maxSelect) {
                              set.add(option.id);
                            }
                          } else {
                            set.remove(option.id);
                          }
                        }),
                      ),
                ],
                if (widget.grocery) ..._substitutionSection(theme),
              ]),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Row(children: [
              if (!widget.flowers) _stepper(tx, theme, dish),
              if (!widget.flowers) const SizedBox(width: 16),
              Expanded(
                child: FilledButton(
                  style: widget.flowers
                      ? FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                          shape: const StadiumBorder())
                      : null,
                  onPressed: _valid && widget.restaurantOpen && dish.available
                      ? _submit
                      : null,
                  child: Text(_valid
                      ? '${widget.flowers ? tx('В корзину', 'Себетке', 'Add to cart') : tx('Добавить', 'Қосу', 'Add')} · ${formatTenge(lineTotalMinor(dish.unit, _unit, _quantity))}'
                      : _max < _step
                          ? tx('Нет в наличии', 'Қолжетімсіз', 'Unavailable')
                          : tx('Выберите опции', 'Нұсқаларды таңдаңыз',
                              'Choose options')),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _stepper(
      String Function(String, String, String) tx, ThemeData theme, Dish dish) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton.outlined(
        tooltip: tx('Меньше', 'Азайту', 'Decrease'),
        onPressed: _quantity - _step >= _step
            ? () => setState(() => _quantity -= _step)
            : null,
        icon: const Icon(Icons.remove_rounded),
      ),
      SizedBox(
          width: dish.weighed ? 76 : 44,
          child: Text(formatQuantity(dish.unit, _quantity),
              textAlign: TextAlign.center, style: theme.textTheme.titleMedium)),
      IconButton.outlined(
        tooltip: tx('Больше', 'Көбейту', 'Increase'),
        onPressed: _quantity + _step <= _max
            ? () => setState(() => _quantity += _step)
            : null,
        icon: const Icon(Icons.add_rounded),
      ),
    ]);
  }

  void _submit() {
    final ids = <String>[];
    if (_substitution == 'CHOSEN') {
      ids.addAll(_chosen);
    }
    Navigator.of(context).pop(CartLine(
      dishId: _dish.id,
      name: _dish.name,
      emoji: _dish.emoji,
      tone: _dish.tone,
      optionIds: [for (final o in _chosenOptions) o.id],
      optionsText: _chosenOptions.map((o) => o.name).join(', '),
      unitPriceMinor: _unit,
      quantity: _quantity,
      unit: _dish.unit,
      maxQuantity: _max,
      substitution: _substitution,
      substituteDishIds: ids,
    ));
  }

  List<Widget> _substitutionSection(ThemeData theme) => [
        const SizedBox(height: 24),
        Text('Если товара не окажется', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
            'Мы не заменим товар без вашего согласия. Замена не будет дороже выбранного товара.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        RadioGroup<String>(
          groupValue: _substitution,
          onChanged: (value) => setState(() => _substitution = value ?? 'NONE'),
          child: const Column(children: [
            RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                value: 'NONE',
                title: Text('Не заменять'),
                subtitle: Text('Уберём товар из заказа и пересчитаем сумму')),
            RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                value: 'ANY_SIMILAR',
                title: Text('Заменить на похожий'),
                subtitle: Text('Подберём ближайший по цене товар')),
            RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                value: 'CHOSEN',
                title: Text('Выбрать допустимые замены')),
          ]),
        ),
        if (_substitution == 'CHOSEN')
          FutureBuilder<List<DishHit>>(
            future: _alternatives,
            builder: (context, state) {
              if (state.connectionState != ConnectionState.done) {
                return const Padding(
                    padding: EdgeInsets.all(12),
                    child: LinearProgressIndicator());
              }
              final list = state.data ?? const <DishHit>[];
              if (state.hasError || list.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                      'Подходящих замен сейчас нет. Выберите другой вариант.'),
                );
              }
              return Column(children: [
                for (final alt in list)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _chosen.contains(alt.id),
                    title: Text(alt.name),
                    subtitle: Text(formatTenge(alt.priceMinor)),
                    secondary: EmojiTile(
                        emoji: alt.emoji, tone: alt.tone, size: 40, radius: 10),
                    onChanged: (on) => setState(() {
                      if (on == true) {
                        if (_chosen.length < 5) _chosen.add(alt.id);
                      } else {
                        _chosen.remove(alt.id);
                      }
                    }),
                  ),
              ]);
            },
          ),
      ];
}

/// Wide product photo of the flowers and gifts card; falls back to a tonal gradient with the emoji.
class _FlowerHero extends StatelessWidget {
  const _FlowerHero({required this.dish});

  final Dish dish;

  @override
  Widget build(BuildContext context) {
    final colors = toneColors(dish.tone);
    final fallback = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white.withValues(alpha: .85), colors.background],
        ),
      ),
      alignment: Alignment.center,
      child: Text(dish.emoji, style: const TextStyle(fontSize: 96)),
    );
    final url = dish.imageUrl;
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: SizedBox(
          height: 220,
          width: double.infinity,
          child: url != null && url.startsWith('https://')
              ? Image.network(url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => fallback,
                  loadingBuilder: (context, child, progress) =>
                      progress == null ? child : fallback)
              : fallback,
        ),
      ),
    );
  }
}
