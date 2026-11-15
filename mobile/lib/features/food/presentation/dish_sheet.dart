import 'package:flutter/material.dart';

import '../data/cart_controller.dart';
import '../data/food_models.dart';
import 'food_widgets.dart';

/// Dish card: description, option groups (radio for single choice, checkboxes for multiple), quantity.
/// Pops a [CartLine] when the customer adds the dish.
class DishSheet extends StatefulWidget {
  const DishSheet(
      {required this.dish, required this.restaurantOpen, super.key});

  final Dish dish;
  final bool restaurantOpen;

  @override
  State<DishSheet> createState() => _DishSheetState();
}

class _DishSheetState extends State<DishSheet> {
  final Map<String, Set<String>> _selected = {};
  int _quantity = 1;

  @override
  void initState() {
    super.initState();
    for (final group in widget.dish.optionGroups) {
      // A required single choice starts on its first option so the price is always valid.
      _selected[group.id] =
          group.single && group.required && group.options.isNotEmpty
              ? {group.options.first.id}
              : <String>{};
    }
  }

  List<DishOption> get _chosen => [
        for (final group in widget.dish.optionGroups)
          for (final option in group.options)
            if (_selected[group.id]!.contains(option.id)) option,
      ];

  int get _unit =>
      widget.dish.priceMinor +
      _chosen.fold(0, (sum, o) => sum + o.priceDeltaMinor);

  bool get _valid => widget.dish.optionGroups.every((g) {
        final count = _selected[g.id]!.length;
        return count >= g.minSelect && count <= g.maxSelect;
      });

  String? _hint(OptionGroup g) {
    if (g.single && g.required) return 'Выберите 1';
    if (g.single) return 'Необязательно';
    if (g.minSelect > 0) return 'Выберите от ${g.minSelect} до ${g.maxSelect}';
    return 'До ${g.maxSelect}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dish = widget.dish;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(children: [
        Expanded(
          child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              children: [
                Center(
                    child: EmojiTile(
                        emoji: dish.emoji,
                        tone: dish.tone,
                        size: 132,
                        radius: 28)),
                const SizedBox(height: 16),
                Text(dish.name, style: theme.textTheme.headlineSmall),
                if (dish.description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(dish.description,
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ],
                const SizedBox(height: 8),
                Text(formatTenge(dish.priceMinor),
                    style: theme.textTheme.titleLarge),
                for (final group in dish.optionGroups) ...[
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(
                        child: Text(group.name,
                            style: theme.textTheme.titleMedium)),
                    Text(_hint(group) ?? '', style: theme.textTheme.bodySmall),
                  ]),
                  if (group.single)
                    RadioGroup<String>(
                      groupValue: _selected[group.id]!.isEmpty
                          ? null
                          : _selected[group.id]!.first,
                      onChanged: (value) => setState(() =>
                          _selected[group.id] = {if (value != null) value}),
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
              ]),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Row(children: [
              IconButton.outlined(
                tooltip: 'Меньше',
                onPressed:
                    _quantity > 1 ? () => setState(() => _quantity--) : null,
                icon: const Icon(Icons.remove_rounded),
              ),
              SizedBox(
                  width: 44,
                  child: Text('$_quantity',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge)),
              IconButton.outlined(
                tooltip: 'Больше',
                onPressed: _quantity < CartController.maxLineQuantity
                    ? () => setState(() => _quantity++)
                    : null,
                icon: const Icon(Icons.add_rounded),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: FilledButton(
                  onPressed: _valid && widget.restaurantOpen && dish.available
                      ? () => Navigator.of(context).pop(CartLine(
                            dishId: dish.id,
                            name: dish.name,
                            emoji: dish.emoji,
                            tone: dish.tone,
                            optionIds: [for (final o in _chosen) o.id],
                            optionsText: _chosen.map((o) => o.name).join(', '),
                            unitPriceMinor: _unit,
                            quantity: _quantity,
                          ))
                      : null,
                  child: Text(_valid
                      ? 'Добавить · ${formatTenge(_unit * _quantity)}'
                      : 'Выберите опции'),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
