/// Models of the KUNDE Groceries API (`/api/v1/groceries`). Money is integer KZT minor units (tiyn); quantities are
/// pieces, or grams for weighed goods (unit `KG`, price per kg, step 100 g).
library;

import '../../food/data/food_models.dart';

class GroceryCategory {
  const GroceryCategory({
    required this.slug,
    required this.nameRu,
    required this.nameKk,
    required this.nameEn,
    required this.icon,
    required this.products,
  });

  final String slug;
  final String nameRu;
  final String nameKk;
  final String nameEn;

  /// Material icon name from the server taxonomy (see `groceryIcon`).
  final String icon;
  final int products;

  String name(String language) => switch (language) {
        'kk' => nameKk,
        'en' => nameEn,
        _ => nameRu,
      };

  factory GroceryCategory.fromJson(Map<String, dynamic> json) =>
      GroceryCategory(
        slug: json['slug'] as String,
        nameRu: json['nameRu'] as String,
        nameKk: json['nameKk'] as String,
        nameEn: json['nameEn'] as String,
        icon: json['icon'] as String? ?? 'category',
        products: (json['products'] as num?)?.toInt() ?? 0,
      );
}

class GroceryProduct {
  const GroceryProduct({
    required this.id,
    required this.name,
    required this.description,
    required this.unit,
    required this.priceMinor,
    required this.available,
    required this.inStock,
    required this.maxQuantity,
    required this.emoji,
    required this.tone,
    required this.storeId,
    required this.storeName,
    this.brand,
    this.category,
    this.compareAtPriceMinor,
    this.discountPercent,
    this.stockQty,
    this.imageUrl,
    this.storeOpen = true,
    this.isNew = false,
    this.onSale = false,
    this.hasRequiredOptions = false,
    this.ratingAvg,
    this.ratingCount = 0,
  });

  final String id;
  final String name;
  final String description;
  final String? brand;
  final String? category;
  final String unit;
  final int priceMinor;
  final int? compareAtPriceMinor;
  final int? discountPercent;
  final bool available;
  final bool inStock;
  final int maxQuantity;
  final int? stockQty;
  final String emoji;
  final String tone;
  final String? imageUrl;
  final String storeId;
  final String storeName;
  final bool storeOpen;
  final bool isNew;
  final bool onSale;

  /// True when the product needs a choice (for example fat content) that only the product page offers.
  final bool hasRequiredOptions;

  /// Average of visible verified reviews; null while the product has none (no invented ratings).
  final double? ratingAvg;
  final int ratingCount;

  bool get weighed => unit == 'KG';
  int get step => weighed ? 100 : 1;

  /// The quantity a first tap on "add" puts in the cart: 500 g of weighed goods (or the stock if smaller), one piece.
  int get defaultQuantity =>
      weighed ? (maxQuantity >= 500 ? 500 : maxQuantity) : 1;

  factory GroceryProduct.fromJson(Map<String, dynamic> json) => GroceryProduct(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        brand: json['brand'] as String?,
        category: json['category'] as String?,
        unit: json['unit'] as String? ?? 'PIECE',
        priceMinor: (json['priceMinor'] as num).toInt(),
        compareAtPriceMinor: (json['compareAtPriceMinor'] as num?)?.toInt(),
        discountPercent: (json['discountPercent'] as num?)?.toInt(),
        available: json['available'] == true,
        inStock: json['inStock'] == true,
        maxQuantity: (json['maxQuantity'] as num?)?.toInt() ?? 20,
        stockQty: (json['stockQty'] as num?)?.toInt(),
        emoji: json['emoji'] as String? ?? '🛒',
        tone: json['tone'] as String? ?? 'green',
        imageUrl: json['imageUrl'] as String?,
        storeId: json['storeId'] as String,
        storeName: json['storeName'] as String,
        storeOpen: json['storeOpen'] != false,
        isNew: json['isNew'] == true,
        onSale: json['onSale'] == true,
        hasRequiredOptions: json['hasRequiredOptions'] == true,
        ratingAvg: (json['ratingAvg'] as num?)?.toDouble(),
        ratingCount: (json['ratingCount'] as num?)?.toInt() ?? 0,
      );
}

class ProductsPage {
  const ProductsPage(
      {required this.items,
      required this.total,
      required this.limit,
      required this.offset});

  final List<GroceryProduct> items;
  final int total;
  final int limit;
  final int offset;

  bool get hasMore => offset + items.length < total;

  factory ProductsPage.fromJson(Map<String, dynamic> json) => ProductsPage(
        items: (json['items'] as List<dynamic>)
            .map((e) => GroceryProduct.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        total: (json['total'] as num).toInt(),
        limit: (json['limit'] as num).toInt(),
        offset: (json['offset'] as num).toInt(),
      );
}

class Nutrition {
  const Nutrition({this.kcal, this.protein, this.fat, this.carbs});

  final int? kcal;
  final double? protein;
  final double? fat;
  final double? carbs;

  factory Nutrition.fromJson(Map<String, dynamic> json) => Nutrition(
        kcal: (json['kcal'] as num?)?.toInt(),
        protein: (json['protein'] as num?)?.toDouble(),
        fat: (json['fat'] as num?)?.toDouble(),
        carbs: (json['carbs'] as num?)?.toDouble(),
      );
}

class ProductDetail {
  const ProductDetail({
    required this.product,
    required this.minQuantity,
    required this.quantityStep,
    required this.optionGroups,
    required this.related,
    this.images = const [],
    this.composition,
    this.storageConditions,
    this.originCountry,
    this.nutrition,
  });

  final GroceryProduct product;
  final String? composition;
  final String? storageConditions;
  final String? originCountry;
  final Nutrition? nutrition;
  final int minQuantity;
  final int quantityStep;
  final List<OptionGroup> optionGroups;
  final List<GroceryProduct> related;

  /// Product photos in display order (HTTPS links supplied by the store); empty when the store has none.
  final List<String> images;

  factory ProductDetail.fromJson(Map<String, dynamic> json) => ProductDetail(
        product:
            GroceryProduct.fromJson(json['product'] as Map<String, dynamic>),
        composition: json['composition'] as String?,
        storageConditions: json['storageConditions'] as String?,
        originCountry: json['originCountry'] as String?,
        nutrition: json['nutrition'] == null
            ? null
            : Nutrition.fromJson(json['nutrition'] as Map<String, dynamic>),
        minQuantity: (json['minQuantity'] as num?)?.toInt() ?? 1,
        quantityStep: (json['quantityStep'] as num?)?.toInt() ?? 1,
        optionGroups: ((json['optionGroups'] as List<dynamic>?) ?? const [])
            .map((e) => OptionGroup.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        images: ((json['images'] as List<dynamic>?) ?? const [])
            .map((e) => e as String)
            .toList(growable: false),
        related: ((json['related'] as List<dynamic>?) ?? const [])
            .map((e) => GroceryProduct.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );
}

/// The filter, search and sort state of the catalog; every field is applied by the server.
class ProductQuery {
  const ProductQuery({
    this.q = '',
    this.category,
    this.storeId,
    this.inStock = false,
    this.onSale = false,
    this.newOnly = false,
    this.brand,
    this.minPriceMinor,
    this.maxPriceMinor,
    this.sort = 'popularity',
  });

  final String q;
  final String? category;
  final String? storeId;
  final bool inStock;
  final bool onSale;
  final bool newOnly;
  final String? brand;
  final int? minPriceMinor;
  final int? maxPriceMinor;
  final String sort;

  static const _unset = Object();

  ProductQuery copyWith({
    String? q,
    Object? category = _unset,
    Object? storeId = _unset,
    bool? inStock,
    bool? onSale,
    bool? newOnly,
    Object? brand = _unset,
    Object? minPriceMinor = _unset,
    Object? maxPriceMinor = _unset,
    String? sort,
  }) =>
      ProductQuery(
        q: q ?? this.q,
        category:
            identical(category, _unset) ? this.category : category as String?,
        storeId: identical(storeId, _unset) ? this.storeId : storeId as String?,
        inStock: inStock ?? this.inStock,
        onSale: onSale ?? this.onSale,
        newOnly: newOnly ?? this.newOnly,
        brand: identical(brand, _unset) ? this.brand : brand as String?,
        minPriceMinor: identical(minPriceMinor, _unset)
            ? this.minPriceMinor
            : minPriceMinor as int?,
        maxPriceMinor: identical(maxPriceMinor, _unset)
            ? this.maxPriceMinor
            : maxPriceMinor as int?,
        sort: sort ?? this.sort,
      );

  /// Filters the customer can reset; the category is the scope of the screen and is not counted.
  int get activeFilters => [
        storeId != null,
        inStock,
        onSale,
        newOnly,
        brand != null,
        minPriceMinor != null || maxPriceMinor != null,
      ].where((v) => v).length;

  Map<String, String> toQuery({required int limit, required int offset}) => {
        if (q.trim().isNotEmpty) 'q': q.trim(),
        if (category != null) 'category': category!,
        if (storeId != null) 'storeId': storeId!,
        if (inStock) 'inStock': 'true',
        if (onSale) 'onSale': 'true',
        if (newOnly) 'newOnly': 'true',
        if (brand != null) 'brand': brand!,
        if (minPriceMinor != null) 'minPriceMinor': '$minPriceMinor',
        if (maxPriceMinor != null) 'maxPriceMinor': '$maxPriceMinor',
        'sort': sort,
        'limit': '$limit',
        'offset': '$offset',
      };
}

class GroceryListSummary {
  const GroceryListSummary(
      {required this.id,
      required this.name,
      required this.items,
      required this.checked});

  final String id;
  final String name;
  final int items;
  final int checked;

  factory GroceryListSummary.fromJson(Map<String, dynamic> json) =>
      GroceryListSummary(
        id: json['id'] as String,
        name: json['name'] as String,
        items: (json['items'] as num).toInt(),
        checked: (json['checked'] as num).toInt(),
      );
}

class GroceryListItem {
  const GroceryListItem({
    required this.productId,
    required this.name,
    required this.unit,
    required this.quantity,
    required this.checked,
    required this.priceMinor,
    required this.inStock,
    required this.emoji,
    required this.storeName,
    this.imageUrl,
  });

  final String productId;
  final String name;
  final String unit;
  final int quantity;
  final bool checked;
  final int priceMinor;
  final bool inStock;
  final String emoji;
  final String? imageUrl;
  final String storeName;

  factory GroceryListItem.fromJson(Map<String, dynamic> json) =>
      GroceryListItem(
        productId: json['productId'] as String,
        name: json['name'] as String,
        unit: json['unit'] as String,
        quantity: (json['quantity'] as num).toInt(),
        checked: json['checked'] == true,
        priceMinor: (json['priceMinor'] as num).toInt(),
        inStock: json['inStock'] == true,
        emoji: json['emoji'] as String? ?? '🛒',
        imageUrl: json['imageUrl'] as String?,
        storeName: json['storeName'] as String? ?? '',
      );
}

class GroceryListDetail {
  const GroceryListDetail(
      {required this.id, required this.name, required this.items});

  final String id;
  final String name;
  final List<GroceryListItem> items;

  factory GroceryListDetail.fromJson(Map<String, dynamic> json) =>
      GroceryListDetail(
        id: json['id'] as String,
        name: json['name'] as String,
        items: (json['items'] as List<dynamic>)
            .map((e) => GroceryListItem.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );
}

/// What the server could not move from a list to the cart: `UNAVAILABLE`, `ALREADY_BOUGHT`, `OTHER_STORE`, `CART_FULL`.
class SkippedItem {
  const SkippedItem(this.productId, this.name, this.reason);

  final String productId;
  final String name;
  final String reason;
}

/// One line of the server cart; [issue] is `UNAVAILABLE`, `OUT_OF_STOCK`, `STOCK_LOW`, `PRICE_CHANGED` or null.
class ServerCartLine {
  const ServerCartLine({
    required this.dishId,
    required this.name,
    required this.unit,
    required this.quantity,
    required this.optionIds,
    required this.substitution,
    required this.substituteDishIds,
    required this.unitPriceMinor,
    required this.maxQuantity,
    required this.emoji,
    this.issue,
    this.previousUnitPriceMinor,
  });

  final String dishId;
  final String name;
  final String unit;
  final int quantity;
  final List<String> optionIds;
  final String substitution;
  final List<String> substituteDishIds;
  final int unitPriceMinor;
  final int? previousUnitPriceMinor;
  final String? issue;
  final int maxQuantity;
  final String emoji;

  factory ServerCartLine.fromJson(Map<String, dynamic> json) => ServerCartLine(
        dishId: json['dishId'] as String,
        name: json['name'] as String,
        unit: json['unit'] as String,
        quantity: (json['quantity'] as num).toInt(),
        optionIds: _strings(json['optionIds']),
        substitution: json['substitution'] as String? ?? 'NONE',
        substituteDishIds: _strings(json['substituteDishIds']),
        unitPriceMinor: (json['unitPriceMinor'] as num).toInt(),
        previousUnitPriceMinor:
            (json['previousUnitPriceMinor'] as num?)?.toInt(),
        issue: json['issue'] as String?,
        maxQuantity: (json['maxQuantity'] as num?)?.toInt() ?? 20,
        emoji: json['emoji'] as String? ?? '🛒',
      );
}

List<String> _strings(Object? value) =>
    ((value as List<dynamic>?) ?? const []).map((e) => e as String).toList();

class ServerCart {
  const ServerCart({
    required this.lines,
    required this.subtotalMinor,
    required this.totalMinor,
    required this.needsUpdate,
    this.restaurantId,
    this.restaurantName,
  });

  final String? restaurantId;
  final String? restaurantName;
  final List<ServerCartLine> lines;
  final int subtotalMinor;
  final int totalMinor;
  final bool needsUpdate;

  bool get isEmpty => restaurantId == null || lines.isEmpty;

  factory ServerCart.fromJson(Map<String, dynamic> json) => ServerCart(
        restaurantId: json['restaurantId'] as String?,
        restaurantName: json['restaurantName'] as String?,
        lines: ((json['lines'] as List<dynamic>?) ?? const [])
            .map((e) => ServerCartLine.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        subtotalMinor: (json['subtotalMinor'] as num?)?.toInt() ?? 0,
        totalMinor: (json['totalMinor'] as num?)?.toInt() ?? 0,
        needsUpdate: json['needsUpdate'] == true,
      );
}

class ProductReview {
  const ProductReview(
      {required this.id,
      required this.rating,
      required this.author,
      this.comment});

  final String id;
  final int rating;
  final String author;
  final String? comment;

  factory ProductReview.fromJson(Map<String, dynamic> json) => ProductReview(
        id: json['id'] as String,
        rating: (json['rating'] as num).toInt(),
        author: json['author'] as String? ?? '',
        comment: json['comment'] as String?,
      );
}

class ProductReviews {
  const ProductReviews(
      {required this.average,
      required this.count,
      required this.distribution,
      required this.reviews});

  final double? average;
  final int count;
  final List<int> distribution;
  final List<ProductReview> reviews;

  factory ProductReviews.fromJson(Map<String, dynamic> json) => ProductReviews(
        average: (json['average'] as num?)?.toDouble(),
        count: (json['count'] as num).toInt(),
        distribution: (json['distribution'] as List<dynamic>)
            .map((e) => (e as num).toInt())
            .toList(growable: false),
        reviews: (json['reviews'] as List<dynamic>)
            .map((e) => ProductReview.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );
}
