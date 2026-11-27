/// Models of the public Flowers & Gifts catalogue (`GET /flowers/**`, ADR-026). Amounts are minor units of KZT.
class FlowersCategory {
  const FlowersCategory({
    required this.code,
    required this.nameRu,
    required this.nameKk,
    required this.nameEn,
    required this.icon,
  });

  factory FlowersCategory.fromJson(Map<String, dynamic> json) =>
      FlowersCategory(
        code: json['code'] as String,
        nameRu: json['nameRu'] as String,
        nameKk: json['nameKk'] as String,
        nameEn: json['nameEn'] as String,
        icon: json['icon'] as String? ?? '',
      );

  final String code;
  final String nameRu;
  final String nameKk;
  final String nameEn;
  final String icon;

  String name(String language) => switch (language) {
        'kk' => nameKk,
        'en' => nameEn,
        _ => nameRu,
      };
}

class FlowersShop {
  const FlowersShop({
    required this.id,
    required this.name,
    required this.description,
    required this.emoji,
    required this.imageUrl,
    required this.deliveryFeeMinor,
    required this.etaMinMinutes,
    required this.etaMaxMinutes,
    required this.open,
    required this.productCount,
  });

  factory FlowersShop.fromJson(Map<String, dynamic> json) => FlowersShop(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        emoji: json['emoji'] as String? ?? '💐',
        imageUrl: json['imageUrl'] as String?,
        deliveryFeeMinor: (json['deliveryFeeMinor'] as num).toInt(),
        etaMinMinutes: (json['etaMinMinutes'] as num).toInt(),
        etaMaxMinutes: (json['etaMaxMinutes'] as num).toInt(),
        open: json['open'] as bool,
        productCount: (json['productCount'] as num?)?.toInt() ?? 0,
      );

  final String id;
  final String name;
  final String description;
  final String emoji;
  final String? imageUrl;
  final int deliveryFeeMinor;
  final int etaMinMinutes;
  final int etaMaxMinutes;
  final bool open;
  final int productCount;
}

class FlowersProduct {
  const FlowersProduct({
    required this.id,
    required this.shopId,
    required this.shopName,
    required this.categoryCode,
    required this.name,
    required this.description,
    required this.priceMinor,
    required this.emoji,
    required this.imageUrl,
    required this.available,
  });

  factory FlowersProduct.fromJson(Map<String, dynamic> json) => FlowersProduct(
        id: json['id'] as String,
        shopId: json['shopId'] as String,
        shopName: json['shopName'] as String? ?? '',
        categoryCode: json['categoryCode'] as String,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        priceMinor: (json['priceMinor'] as num).toInt(),
        emoji: json['emoji'] as String? ?? '💐',
        imageUrl: json['imageUrl'] as String?,
        available: json['available'] as bool,
      );

  final String id;
  final String shopId;
  final String shopName;
  final String categoryCode;
  final String name;
  final String description;
  final int priceMinor;
  final String emoji;
  final String? imageUrl;
  final bool available;
}

class FlowersShopDetail {
  const FlowersShopDetail({required this.shop, required this.products});

  factory FlowersShopDetail.fromJson(Map<String, dynamic> json) =>
      FlowersShopDetail(
        shop: FlowersShop.fromJson(json['shop'] as Map<String, dynamic>),
        products: [
          for (final p in json['products'] as List<dynamic>)
            FlowersProduct.fromJson(p as Map<String, dynamic>),
        ],
      );

  final FlowersShop shop;
  final List<FlowersProduct> products;
}

/// One line of a quote or of a placed order.
class FlowersLine {
  const FlowersLine({
    required this.productId,
    required this.name,
    required this.emoji,
    required this.unitPriceMinor,
    required this.quantity,
    required this.lineTotalMinor,
  });

  factory FlowersLine.fromJson(Map<String, dynamic> json) => FlowersLine(
        productId: json['productId'] as String,
        name: json['name'] as String,
        emoji: json['emoji'] as String? ?? '💐',
        unitPriceMinor: (json['unitPriceMinor'] as num).toInt(),
        quantity: (json['quantity'] as num).toInt(),
        lineTotalMinor: (json['lineTotalMinor'] as num).toInt(),
      );

  final String productId;
  final String name;
  final String emoji;
  final int unitPriceMinor;
  final int quantity;
  final int lineTotalMinor;
}

/// Server price of a cart (`POST /flowers/cart/quote`); the total is what checkout must confirm.
class FlowersQuote {
  const FlowersQuote({
    required this.lines,
    required this.subtotalMinor,
    required this.deliveryFeeMinor,
    required this.totalMinor,
  });

  factory FlowersQuote.fromJson(Map<String, dynamic> json) => FlowersQuote(
        lines: [
          for (final l in json['lines'] as List<dynamic>)
            FlowersLine.fromJson(l as Map<String, dynamic>),
        ],
        subtotalMinor: (json['subtotalMinor'] as num).toInt(),
        deliveryFeeMinor: (json['deliveryFeeMinor'] as num).toInt(),
        totalMinor: (json['totalMinor'] as num).toInt(),
      );

  final List<FlowersLine> lines;
  final int subtotalMinor;
  final int deliveryFeeMinor;
  final int totalMinor;
}

class FlowersSlot {
  const FlowersSlot({required this.startsAt, required this.endsAt});

  factory FlowersSlot.fromJson(Map<String, dynamic> json) => FlowersSlot(
        startsAt: DateTime.parse(json['startsAt'] as String),
        endsAt: DateTime.parse(json['endsAt'] as String),
      );

  final DateTime startsAt;
  final DateTime endsAt;

  /// The exact string the server offered; it is sent back unchanged when ordering.
  String get startsAtIso => startsAt.toUtc().toIso8601String();
}

class FlowersOrder {
  const FlowersOrder({
    required this.id,
    required this.shopName,
    required this.status,
    required this.totalMinor,
    required this.deliveryMode,
    required this.scheduledFrom,
    required this.scheduledTo,
    required this.addressText,
    required this.recipientName,
    required this.cardText,
    required this.placedAt,
    required this.items,
    required this.subtotalMinor,
    required this.deliveryFeeMinor,
    this.courierAssigned = false,
    this.etaMinutes,
  });

  factory FlowersOrder.fromJson(Map<String, dynamic> json) => FlowersOrder(
        id: json['id'] as String,
        shopName: json['shopName'] as String,
        status: json['status'] as String,
        totalMinor: (json['totalMinor'] as num).toInt(),
        subtotalMinor: (json['subtotalMinor'] as num).toInt(),
        deliveryFeeMinor: (json['deliveryFeeMinor'] as num).toInt(),
        deliveryMode: json['deliveryMode'] as String,
        scheduledFrom: json['scheduledFrom'] == null
            ? null
            : DateTime.parse(json['scheduledFrom'] as String).toLocal(),
        scheduledTo: json['scheduledTo'] == null
            ? null
            : DateTime.parse(json['scheduledTo'] as String).toLocal(),
        addressText: json['addressText'] as String,
        recipientName: json['recipientName'] as String?,
        cardText: json['cardText'] as String?,
        placedAt: DateTime.parse(json['placedAt'] as String).toLocal(),
        courierAssigned: json['courierAssigned'] == true,
        etaMinutes: (json['etaMinutes'] as num?)?.toInt(),
        items: [
          for (final l in json['items'] as List<dynamic>)
            FlowersLine.fromJson(l as Map<String, dynamic>),
        ],
      );

  final String id;
  final String shopName;

  /// PLACED, ACCEPTED, ASSEMBLING, ON_THE_WAY, DELIVERED or CANCELLED.
  final String status;
  final int totalMinor;
  final int subtotalMinor;
  final int deliveryFeeMinor;
  final String deliveryMode;
  final DateTime? scheduledFrom;
  final DateTime? scheduledTo;
  final String addressText;
  final String? recipientName;
  final String? cardText;
  final DateTime placedAt;
  final List<FlowersLine> items;

  /// A courier has taken the order (assigned, on the way or done).
  final bool courierAssigned;

  /// Minutes to arrival while the order is on its way: an estimate from the shop's stated delivery time, not GPS.
  final int? etaMinutes;

  bool get cancellable => status == 'PLACED';
  bool get active => status != 'DELIVERED' && status != 'CANCELLED';
}
