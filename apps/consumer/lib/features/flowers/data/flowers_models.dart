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
