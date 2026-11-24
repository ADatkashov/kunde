import 'package:flutter/foundation.dart';

import 'package:kunde_models/food_models.dart';

/// One cart line: a dish with a fixed option selection. Prices here are only a preview; the server
/// recomputes everything in `cart/quote` and at checkout.
///
/// [quantity] is pieces, or grams for weighed goods ([unit] `KG`, step 100 g).
class CartLine {
  CartLine({
    required this.dishId,
    required this.name,
    required this.emoji,
    required this.tone,
    required this.optionIds,
    required this.optionsText,
    required this.unitPriceMinor,
    required this.quantity,
    this.unit = 'PIECE',
    this.maxQuantity = 20,
    this.substitution = 'NONE',
    this.substituteDishIds = const [],
  });

  final String dishId;
  final String name;
  final String emoji;
  final String tone;
  final List<String> optionIds;
  final String optionsText;
  final int unitPriceMinor;
  int quantity;
  final String unit;

  /// Per-line limit (stock-aware) known when the line was added.
  final int maxQuantity;

  /// `NONE` (never replace), `ANY_SIMILAR` or `CHOSEN` (only [substituteDishIds]).
  final String substitution;
  final List<String> substituteDishIds;

  bool get weighed => unit == 'KG';
  int get step => weighed ? 100 : 1;
  int get totalMinor => lineTotalMinor(unit, unitPriceMinor, quantity);

  String get key =>
      '$dishId|${(List.of(optionIds)..sort()).join(',')}|$substitution|${(List.of(substituteDishIds)..sort()).join(',')}';

  Map<String, dynamic> toRequest() => {
        'dishId': dishId,
        'quantity': quantity,
        'optionIds': optionIds,
        'substitution': substitution,
        'substituteDishIds': substituteDishIds,
      };
}

/// The in-app cart. A cart holds products of exactly one restaurant or store.
class CartController extends ChangeNotifier {
  static const maxLineQuantity = 20;

  Restaurant? _restaurant;
  final List<CartLine> _lines = [];

  Restaurant? get restaurant => _restaurant;
  List<CartLine> get lines => List.unmodifiable(_lines);
  bool get isEmpty => _lines.isEmpty;

  /// Badge count: one per piece, one per weighed line.
  int get itemCount =>
      _lines.fold(0, (sum, line) => sum + (line.weighed ? 1 : line.quantity));
  int get previewSubtotalMinor =>
      _lines.fold(0, (sum, line) => sum + line.totalMinor);

  /// True when adding from [restaurantId] would drop the current cart contents.
  bool conflictsWith(String restaurantId) =>
      _restaurant != null &&
      _restaurant!.id != restaurantId &&
      _lines.isNotEmpty;

  void add(Restaurant restaurant, CartLine line) {
    if (conflictsWith(restaurant.id)) {
      _lines.clear();
    }
    _restaurant = restaurant;
    final existing = _lines.where((l) => l.key == line.key).firstOrNull;
    if (existing != null) {
      existing.quantity = (existing.quantity + line.quantity)
          .clamp(existing.step, existing.maxQuantity);
    } else {
      _lines.add(line);
    }
    notifyListeners();
  }

  /// Sets a line quantity (pieces or grams); zero or less removes it, more than the limit is capped.
  void setQuantity(CartLine line, int quantity) {
    if (quantity <= 0) {
      _lines.remove(line);
      if (_lines.isEmpty) _restaurant = null;
    } else {
      line.quantity = quantity.clamp(line.step, line.maxQuantity);
    }
    notifyListeners();
  }

  void clear() {
    _lines.clear();
    _restaurant = null;
    notifyListeners();
  }
}
