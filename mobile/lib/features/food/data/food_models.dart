/// Models of the KUNDE Food API (`/api/v1/food`). Money is integer KZT minor units (tiyn).
library;

import 'package:flutter/painting.dart';

/// Formats tiyn as tenge: `5 800 ₸` (fraction shown only when non-zero).
String formatTenge(int minor) {
  final negative = minor < 0;
  final abs = negative ? -minor : minor;
  final whole = abs ~/ 100;
  final fraction = abs % 100;
  final digits = whole.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  final fractionText =
      fraction == 0 ? '' : ',${fraction.toString().padLeft(2, '0')}';
  return '${negative ? '-' : ''}$buffer$fractionText ₸';
}

/// Quantity text: pieces as `3 шт`, weighed goods (grams) as `500 г` / `1,5 кг`.
String formatQuantity(String unit, int quantity) {
  if (unit != 'KG') return '$quantity шт';
  if (quantity < 1000) return '$quantity г';
  final kg = quantity / 1000;
  final text = kg == kg.roundToDouble()
      ? kg.toStringAsFixed(0)
      : kg
          .toStringAsFixed(2)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceAll('.', ',');
  return '$text кг';
}

/// Price suffix: `за кг` for weighed goods.
String unitPriceLabel(String unit, int priceMinor) =>
    unit == 'KG' ? '${formatTenge(priceMinor)} / кг' : formatTenge(priceMinor);

/// Line total in tiyn: pieces multiply, weighed goods price per kg x grams, rounded like the server.
int lineTotalMinor(String unit, int unitPriceMinor, int quantity) =>
    unit == 'KG'
        ? (unitPriceMinor * quantity + 500) ~/ 1000
        : unitPriceMinor * quantity;

/// Soft background / foreground pair for the emoji "photo" tiles (no licensed photos are bundled).
({Color background, Color foreground}) toneColors(String tone) =>
    switch (tone) {
      'red' => (
          background: const Color(0xFFFFE1DC),
          foreground: const Color(0xFF8C1D12)
        ),
      'amber' => (
          background: const Color(0xFFFFF0CC),
          foreground: const Color(0xFF7A4B00)
        ),
      'green' => (
          background: const Color(0xFFDDF4E2),
          foreground: const Color(0xFF145A2A)
        ),
      'blue' => (
          background: const Color(0xFFDDEBFF),
          foreground: const Color(0xFF12447F)
        ),
      _ => (
          background: const Color(0xFFFFE8D2),
          foreground: const Color(0xFF8A3B00)
        ),
    };

class Restaurant {
  const Restaurant({
    required this.id,
    required this.name,
    required this.cuisine,
    required this.description,
    required this.emoji,
    required this.tone,
    required this.deliveryFeeMinor,
    required this.minOrderMinor,
    required this.etaMinMinutes,
    required this.etaMaxMinutes,
    required this.open,
    required this.synthetic,
    this.vertical = 'FOOD',
    this.imageUrl,
  });

  final String id;
  final String name;
  final String? imageUrl;

  /// `FOOD` (restaurants) or `GROCERY` (stores); stores reuse the same catalog, cart and order model.
  final String vertical;
  final String cuisine;
  final String description;
  final String emoji;
  final String tone;
  final int deliveryFeeMinor;
  final int minOrderMinor;
  final int etaMinMinutes;
  final int etaMaxMinutes;
  final bool open;
  final bool synthetic;

  String get eta => '$etaMinMinutes–$etaMaxMinutes мин';

  factory Restaurant.fromJson(Map<String, dynamic> json) => Restaurant(
        id: json['id'] as String,
        name: json['name'] as String,
        cuisine: json['cuisine'] as String,
        description: json['description'] as String? ?? '',
        emoji: json['emoji'] as String? ?? '🍽️',
        tone: json['tone'] as String? ?? 'orange',
        deliveryFeeMinor: (json['deliveryFeeMinor'] as num).toInt(),
        minOrderMinor: (json['minOrderMinor'] as num).toInt(),
        etaMinMinutes: (json['etaMinMinutes'] as num).toInt(),
        etaMaxMinutes: (json['etaMaxMinutes'] as num).toInt(),
        open: json['open'] as bool? ?? false,
        synthetic: json['synthetic'] as bool? ?? false,
        vertical: json['vertical'] as String? ?? 'FOOD',
        imageUrl: json['imageUrl'] as String?,
      );
}

class DishOption {
  const DishOption(
      {required this.id, required this.name, required this.priceDeltaMinor});

  final String id;
  final String name;
  final int priceDeltaMinor;

  factory DishOption.fromJson(Map<String, dynamic> json) => DishOption(
        id: json['id'] as String,
        name: json['name'] as String,
        priceDeltaMinor: (json['priceDeltaMinor'] as num).toInt(),
      );
}

class OptionGroup {
  const OptionGroup({
    required this.id,
    required this.name,
    required this.minSelect,
    required this.maxSelect,
    required this.options,
  });

  final String id;
  final String name;
  final int minSelect;
  final int maxSelect;
  final List<DishOption> options;

  bool get single => maxSelect == 1;
  bool get required => minSelect > 0;

  factory OptionGroup.fromJson(Map<String, dynamic> json) => OptionGroup(
        id: json['id'] as String,
        name: json['name'] as String,
        minSelect: (json['minSelect'] as num).toInt(),
        maxSelect: (json['maxSelect'] as num).toInt(),
        options: (json['options'] as List<dynamic>)
            .map((e) => DishOption.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );
}

class Dish {
  const Dish({
    required this.id,
    required this.name,
    required this.description,
    required this.priceMinor,
    required this.emoji,
    required this.tone,
    required this.available,
    required this.optionGroups,
    this.unit = 'PIECE',
    this.maxQuantity = 20,
    this.stockQty,
    this.imageUrl,
  });

  /// `PIECE` or `KG` (price per kg, quantities in grams).
  final String unit;

  /// Per-line limit including stock (pieces or grams).
  final int maxQuantity;
  final int? stockQty;
  final String? imageUrl;
  bool get weighed => unit == 'KG';
  final String id;
  final String name;
  final String description;
  final int priceMinor;
  final String emoji;
  final String tone;
  final bool available;
  final List<OptionGroup> optionGroups;

  factory Dish.fromJson(Map<String, dynamic> json) => Dish(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        priceMinor: (json['priceMinor'] as num).toInt(),
        emoji: json['emoji'] as String? ?? '🍽️',
        tone: json['tone'] as String? ?? 'orange',
        available: json['available'] as bool? ?? false,
        optionGroups: (json['optionGroups'] as List<dynamic>? ?? const [])
            .map((e) => OptionGroup.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        unit: json['unit'] as String? ?? 'PIECE',
        maxQuantity: (json['maxQuantity'] as num?)?.toInt() ?? 20,
        stockQty: (json['stockQty'] as num?)?.toInt(),
        imageUrl: json['imageUrl'] as String?,
      );
}

class MenuSection {
  const MenuSection(
      {required this.id, required this.name, required this.dishes});

  final String id;
  final String name;
  final List<Dish> dishes;

  factory MenuSection.fromJson(Map<String, dynamic> json) => MenuSection(
        id: json['id'] as String,
        name: json['name'] as String,
        dishes: (json['dishes'] as List<dynamic>)
            .map((e) => Dish.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );
}

class RestaurantMenu {
  const RestaurantMenu({required this.restaurant, required this.sections});

  final Restaurant restaurant;
  final List<MenuSection> sections;

  factory RestaurantMenu.fromJson(Map<String, dynamic> json) => RestaurantMenu(
        restaurant:
            Restaurant.fromJson(json['restaurant'] as Map<String, dynamic>),
        sections: (json['sections'] as List<dynamic>)
            .map((e) => MenuSection.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );
}

class DishHit {
  const DishHit({
    required this.id,
    required this.name,
    required this.priceMinor,
    required this.emoji,
    required this.tone,
    required this.available,
    required this.restaurantId,
    required this.restaurantName,
  });

  final String id;
  final String name;
  final int priceMinor;
  final String emoji;
  final String tone;
  final bool available;
  final String restaurantId;
  final String restaurantName;

  factory DishHit.fromJson(Map<String, dynamic> json) => DishHit(
        id: json['id'] as String,
        name: json['name'] as String,
        priceMinor: (json['priceMinor'] as num).toInt(),
        emoji: json['emoji'] as String? ?? '🍽️',
        tone: json['tone'] as String? ?? 'orange',
        available: json['available'] as bool? ?? false,
        restaurantId: json['restaurantId'] as String,
        restaurantName: json['restaurantName'] as String,
      );
}

class FoodSearchResult {
  const FoodSearchResult({required this.restaurants, required this.dishes});

  final List<Restaurant> restaurants;
  final List<DishHit> dishes;

  bool get isEmpty => restaurants.isEmpty && dishes.isEmpty;

  factory FoodSearchResult.fromJson(Map<String, dynamic> json) =>
      FoodSearchResult(
        restaurants: (json['restaurants'] as List<dynamic>)
            .map((e) => Restaurant.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        dishes: (json['dishes'] as List<dynamic>)
            .map((e) => DishHit.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );
}

class QuoteLine {
  const QuoteLine({
    required this.dishId,
    required this.name,
    required this.optionsText,
    required this.unitPriceMinor,
    required this.quantity,
    required this.lineTotalMinor,
    this.unit = 'PIECE',
  });

  final String unit;
  final String dishId;
  final String name;
  final String optionsText;
  final int unitPriceMinor;
  final int quantity;
  final int lineTotalMinor;

  factory QuoteLine.fromJson(Map<String, dynamic> json) => QuoteLine(
        dishId: json['dishId'] as String,
        name: json['name'] as String,
        optionsText: json['optionsText'] as String? ?? '',
        unitPriceMinor: (json['unitPriceMinor'] as num).toInt(),
        quantity: (json['quantity'] as num).toInt(),
        lineTotalMinor: (json['lineTotalMinor'] as num).toInt(),
        unit: json['unit'] as String? ?? 'PIECE',
      );
}

class FoodQuote {
  const FoodQuote({
    required this.restaurantName,
    required this.lines,
    required this.subtotalMinor,
    required this.deliveryFeeMinor,
    required this.totalMinor,
    required this.minOrderMinor,
  });

  final String restaurantName;
  final List<QuoteLine> lines;
  final int subtotalMinor;
  final int deliveryFeeMinor;
  final int totalMinor;
  final int minOrderMinor;

  factory FoodQuote.fromJson(Map<String, dynamic> json) => FoodQuote(
        restaurantName: json['restaurantName'] as String,
        lines: (json['lines'] as List<dynamic>)
            .map((e) => QuoteLine.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        subtotalMinor: (json['subtotalMinor'] as num).toInt(),
        deliveryFeeMinor: (json['deliveryFeeMinor'] as num).toInt(),
        totalMinor: (json['totalMinor'] as num).toInt(),
        minOrderMinor: (json['minOrderMinor'] as num).toInt(),
      );
}

class TimelineEntry {
  const TimelineEntry({required this.status, required this.at});

  final String status;
  final DateTime at;

  factory TimelineEntry.fromJson(Map<String, dynamic> json) => TimelineEntry(
      status: json['status'] as String,
      at: DateTime.parse(json['at'] as String));
}

class OrderLine {
  const OrderLine({
    required this.name,
    required this.optionsText,
    required this.quantity,
    required this.lineTotalMinor,
    this.unit = 'PIECE',
    this.fulfillmentStatus = 'PENDING',
    this.replacedByName,
    this.finalLineTotalMinor,
    this.substitution = 'NONE',
  });

  final String unit;

  /// `PENDING` until the store collects the order, then `OK`, `SUBSTITUTED` or `REMOVED`.
  final String fulfillmentStatus;
  final String? replacedByName;
  final int? finalLineTotalMinor;
  final String substitution;
  final String name;
  final String optionsText;
  final int quantity;
  final int lineTotalMinor;

  factory OrderLine.fromJson(Map<String, dynamic> json) => OrderLine(
        name: json['name'] as String,
        optionsText: json['optionsText'] as String? ?? '',
        quantity: (json['quantity'] as num).toInt(),
        lineTotalMinor: (json['lineTotalMinor'] as num).toInt(),
        unit: json['unit'] as String? ?? 'PIECE',
        fulfillmentStatus: json['fulfillmentStatus'] as String? ?? 'PENDING',
        replacedByName: json['replacedByName'] as String?,
        finalLineTotalMinor: (json['finalLineTotalMinor'] as num?)?.toInt(),
        substitution: json['substitution'] as String? ?? 'NONE',
      );
}

/// Order statuses in delivery order; `CANCELLED` is terminal and outside the flow.
const orderFlow = [
  'PLACED',
  'ACCEPTED',
  'PREPARING',
  'ON_THE_WAY',
  'DELIVERED'
];

String orderStatusLabel(String status) => switch (status) {
      'PLACED' => 'Заказ оформлен',
      'ACCEPTED' => 'Ресторан принял заказ',
      'PREPARING' => 'Готовится',
      'ON_THE_WAY' => 'Курьер в пути',
      'DELIVERED' => 'Доставлен',
      'CANCELLED' => 'Отменён',
      _ => status,
    };

class FoodOrder {
  const FoodOrder({
    required this.id,
    required this.restaurantId,
    required this.restaurantName,
    required this.status,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.subtotalMinor,
    required this.deliveryFeeMinor,
    required this.totalMinor,
    required this.addressLabel,
    required this.addressText,
    required this.comment,
    required this.placedAt,
    required this.items,
    required this.timeline,
    required this.cancellable,
    this.vertical = 'FOOD',
    this.finalTotalMinor,
    this.hasChanges = false,
    this.cancelledBy,
    this.cancelReason,
  });

  /// Who cancelled (`CUSTOMER`, `PARTNER`, `SYSTEM`) and the partner's reason, if any.
  final String? cancelledBy;
  final String? cancelReason;

  /// Total after the store replaced or removed unavailable products; null until collected.
  final int? finalTotalMinor;
  final bool hasChanges;
  final String vertical;
  final String id;
  final String restaurantId;
  final String restaurantName;
  final String status;
  final String paymentMethod;
  final String paymentStatus;
  final int subtotalMinor;
  final int deliveryFeeMinor;
  final int totalMinor;
  final String addressLabel;
  final String addressText;
  final String? comment;
  final DateTime placedAt;
  final List<OrderLine> items;
  final List<TimelineEntry> timeline;
  final bool cancellable;

  bool get terminal => status == 'DELIVERED' || status == 'CANCELLED';

  String get paymentLabel => switch (paymentStatus) {
        'NO_PAYMENT' => 'Тестовый заказ — без оплаты',
        'TEST_PAID' => 'Тестовая карта (DEV) — оплачено',
        'PAY_ON_RECEIPT' => 'Наличными при получении',
        'VOIDED' => 'Платёж аннулирован',
        _ => paymentStatus,
      };

  factory FoodOrder.fromJson(Map<String, dynamic> json) => FoodOrder(
        id: json['id'] as String,
        restaurantId: json['restaurantId'] as String,
        restaurantName: json['restaurantName'] as String,
        status: json['status'] as String,
        paymentMethod: json['paymentMethod'] as String,
        paymentStatus: json['paymentStatus'] as String,
        subtotalMinor: (json['subtotalMinor'] as num).toInt(),
        deliveryFeeMinor: (json['deliveryFeeMinor'] as num).toInt(),
        totalMinor: (json['totalMinor'] as num).toInt(),
        addressLabel: json['addressLabel'] as String,
        addressText: json['addressText'] as String,
        comment: json['comment'] as String?,
        placedAt: DateTime.parse(json['placedAt'] as String).toLocal(),
        items: (json['items'] as List<dynamic>)
            .map((e) => OrderLine.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        timeline: (json['timeline'] as List<dynamic>)
            .map((e) => TimelineEntry.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        cancellable: json['cancellable'] as bool? ?? false,
        vertical: json['vertical'] as String? ?? 'FOOD',
        finalTotalMinor: (json['finalTotalMinor'] as num?)?.toInt(),
        hasChanges: json['hasChanges'] as bool? ?? false,
        cancelledBy: json['cancelledBy'] as String?,
        cancelReason: json['cancelReason'] as String?,
      );
}

class RepeatItem {
  const RepeatItem({
    required this.dishId,
    required this.name,
    required this.quantity,
    required this.optionIds,
    this.unit = 'PIECE',
    this.substitution = 'NONE',
    this.substituteDishIds = const [],
  });

  final String dishId;
  final String name;
  final int quantity;
  final List<String> optionIds;
  final String unit;
  final String substitution;
  final List<String> substituteDishIds;
}

class RepeatResult {
  const RepeatResult({
    required this.restaurantId,
    required this.restaurantName,
    required this.items,
    required this.skipped,
  });

  final String restaurantId;
  final String restaurantName;
  final List<RepeatItem> items;
  final List<String> skipped;

  factory RepeatResult.fromJson(Map<String, dynamic> json) => RepeatResult(
        restaurantId: json['restaurantId'] as String,
        restaurantName: json['restaurantName'] as String,
        items: (json['items'] as List<dynamic>)
            .map((e) => e as Map<String, dynamic>)
            .map((e) => RepeatItem(
                  dishId: e['dishId'] as String,
                  name: e['name'] as String,
                  quantity: (e['quantity'] as num).toInt(),
                  optionIds: (e['optionIds'] as List<dynamic>).cast<String>(),
                  unit: e['unit'] as String? ?? 'PIECE',
                  substitution: e['substitution'] as String? ?? 'NONE',
                  substituteDishIds:
                      (e['substituteDishIds'] as List<dynamic>? ?? const [])
                          .cast<String>(),
                ))
            .toList(growable: false),
        skipped: (json['skipped'] as List<dynamic>).cast<String>(),
      );
}
