import 'package:flutter/foundation.dart';

/// One product line of the flowers cart. Prices here are only a preview; the server prices the cart again.
class FlowersCartLine {
  FlowersCartLine({
    required this.productId,
    required this.name,
    required this.emoji,
    required this.unitPriceMinor,
    this.quantity = 1,
  });

  final String productId;
  final String name;
  final String emoji;
  final int unitPriceMinor;
  int quantity;

  int get totalMinor => unitPriceMinor * quantity;
}

/// In-app cart of Flowers & Gifts. A cart holds products of exactly one shop (the server accepts one shop per order).
class FlowersCart extends ChangeNotifier {
  static const maxLineQuantity = 20;
  static const maxLines = 20;

  String? _shopId;
  String? _shopName;
  int _deliveryFeeMinor = 0;
  final List<FlowersCartLine> _lines = [];

  String? get shopId => _shopId;
  String? get shopName => _shopName;
  int get deliveryFeeMinor => _deliveryFeeMinor;
  List<FlowersCartLine> get lines => List.unmodifiable(_lines);
  bool get isEmpty => _lines.isEmpty;
  int get itemCount => _lines.fold(0, (sum, l) => sum + l.quantity);
  int get subtotalMinor => _lines.fold(0, (sum, l) => sum + l.totalMinor);

  /// True when [shopId] differs from the shop of a non-empty cart (the caller asks before replacing it).
  bool conflictsWith(String shopId) =>
      _shopId != null && _shopId != shopId && _lines.isNotEmpty;

  /// Adds one piece. Returns false when the cart is full or the line is at the limit.
  bool add({
    required String shopId,
    required String shopName,
    required int deliveryFeeMinor,
    required String productId,
    required String name,
    required String emoji,
    required int unitPriceMinor,
  }) {
    if (conflictsWith(shopId)) {
      throw StateError('The cart holds another shop; clear it first');
    }
    _shopId = shopId;
    _shopName = shopName;
    _deliveryFeeMinor = deliveryFeeMinor;
    final existing = _lines.where((l) => l.productId == productId);
    if (existing.isNotEmpty) {
      if (existing.first.quantity >= maxLineQuantity) return false;
      existing.first.quantity++;
    } else {
      if (_lines.length >= maxLines) return false;
      _lines.add(FlowersCartLine(
          productId: productId,
          name: name,
          emoji: emoji,
          unitPriceMinor: unitPriceMinor));
    }
    notifyListeners();
    return true;
  }

  /// Sets the quantity of a line; zero or less removes it.
  void setQuantity(String productId, int quantity) {
    final index = _lines.indexWhere((l) => l.productId == productId);
    if (index < 0) return;
    if (quantity <= 0) {
      _lines.removeAt(index);
    } else {
      _lines[index].quantity =
          quantity > maxLineQuantity ? maxLineQuantity : quantity;
    }
    if (_lines.isEmpty) {
      _shopId = null;
      _shopName = null;
    }
    notifyListeners();
  }

  void clear() {
    _lines.clear();
    _shopId = null;
    _shopName = null;
    notifyListeners();
  }

  List<Map<String, dynamic>> toRequestItems() => [
        for (final l in _lines)
          {'productId': l.productId, 'quantity': l.quantity},
      ];
}
