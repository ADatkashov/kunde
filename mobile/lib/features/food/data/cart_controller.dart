import 'package:flutter/foundation.dart';

import 'food_models.dart';

/// One cart line: a dish with a fixed option selection. Prices here are only a preview; the server
/// recomputes everything in `cart/quote` and at checkout.
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
  });

  final String dishId;
  final String name;
  final String emoji;
  final String tone;
  final List<String> optionIds;
  final String optionsText;
  final int unitPriceMinor;
  int quantity;

  int get totalMinor => unitPriceMinor * quantity;

  String get key => '$dishId|${(List.of(optionIds)..sort()).join(',')}';

  Map<String, dynamic> toRequest() =>
      {'dishId': dishId, 'quantity': quantity, 'optionIds': optionIds};
}

/// The in-app cart. A cart holds dishes of exactly one restaurant.
class CartController extends ChangeNotifier {
  static const maxLineQuantity = 20;

  Restaurant? _restaurant;
  final List<CartLine> _lines = [];

  Restaurant? get restaurant => _restaurant;
  List<CartLine> get lines => List.unmodifiable(_lines);
  bool get isEmpty => _lines.isEmpty;
  int get itemCount => _lines.fold(0, (sum, line) => sum + line.quantity);
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
      existing.quantity =
          (existing.quantity + line.quantity).clamp(1, maxLineQuantity);
    } else {
      _lines.add(line);
    }
    notifyListeners();
  }

  void setQuantity(CartLine line, int quantity) {
    if (quantity <= 0) {
      _lines.remove(line);
      if (_lines.isEmpty) _restaurant = null;
    } else {
      line.quantity = quantity.clamp(1, maxLineQuantity);
    }
    notifyListeners();
  }

  void clear() {
    _lines.clear();
    _restaurant = null;
    notifyListeners();
  }
}
