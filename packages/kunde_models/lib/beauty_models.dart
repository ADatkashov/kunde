import 'package:kunde_models/booking_models.dart' show parseVenueTime;

List<String> _strings(Object? value) =>
    ((value as List<dynamic>?) ?? const []).cast<String>();

double? _double(Object? value) => (value as num?)?.toDouble();

class BeautyCategory {
  const BeautyCategory({
    required this.code,
    required this.nameRu,
    required this.nameKk,
    required this.nameEn,
    required this.icon,
    required this.featured,
  });

  final String code;
  final String nameRu;
  final String nameKk;
  final String nameEn;
  final String icon;
  final bool featured;

  String name(String languageCode) => switch (languageCode) {
        'kk' => nameKk,
        'en' => nameEn,
        _ => nameRu,
      };

  factory BeautyCategory.fromJson(Map<String, dynamic> json) => BeautyCategory(
        code: json['code'] as String,
        nameRu: json['nameRu'] as String,
        nameKk: json['nameKk'] as String,
        nameEn: json['nameEn'] as String,
        icon: json['icon'] as String,
        featured: json['featured'] == true,
      );
}

class BeautySalon {
  const BeautySalon({
    required this.id,
    required this.name,
    required this.addressText,
    required this.categories,
    required this.verified,
    required this.reviewCount,
    this.imageUrl,
    this.latitude,
    this.longitude,
    this.rating,
    this.fromPriceMinor,
    this.discountPercent,
    this.distanceMeters,
  });

  final String id;
  final String name;
  final String addressText;
  final List<String> categories;
  final bool verified;
  final int reviewCount;
  final String? imageUrl;
  final double? latitude;
  final double? longitude;
  final double? rating;
  final int? fromPriceMinor;
  final int? discountPercent;
  final int? distanceMeters;

  factory BeautySalon.fromJson(Map<String, dynamic> json) => BeautySalon(
        id: json['id'] as String,
        name: json['name'] as String,
        addressText: json['addressText'] as String,
        categories: _strings(json['categories']),
        verified: json['verified'] == true,
        reviewCount: (json['reviewCount'] as num?)?.toInt() ?? 0,
        imageUrl: json['imageUrl'] as String?,
        latitude: _double(json['latitude']),
        longitude: _double(json['longitude']),
        rating: _double(json['rating']),
        fromPriceMinor: (json['fromPriceMinor'] as num?)?.toInt(),
        discountPercent: (json['discountPercent'] as num?)?.toInt(),
        distanceMeters: (json['distanceMeters'] as num?)?.toInt(),
      );
}

class BeautyService {
  const BeautyService({
    required this.id,
    required this.name,
    required this.description,
    required this.durationMinutes,
    required this.priceMinor,
    required this.priceFrom,
    required this.tags,
    this.categoryCode,
  });

  final String id;
  final String name;
  final String description;
  final int durationMinutes;
  final int priceMinor;

  /// The price is "from" the shown amount.
  final bool priceFrom;
  final List<String> tags;
  final String? categoryCode;

  factory BeautyService.fromJson(Map<String, dynamic> json) => BeautyService(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        durationMinutes: (json['durationMinutes'] as num).toInt(),
        priceMinor: (json['priceMinor'] as num).toInt(),
        priceFrom: json['priceFrom'] == true,
        tags: _strings(json['tags']),
        categoryCode: json['categoryCode'] as String?,
      );
}

class BeautyMaster {
  const BeautyMaster({
    required this.id,
    required this.name,
    required this.bio,
    required this.specialty,
    required this.reviewCount,
    required this.serviceIds,
    this.experienceYears,
    this.rating,
    this.nextSlotAt,
  });

  final String id;
  final String name;
  final String bio;
  final String specialty;
  final int reviewCount;
  final List<String> serviceIds;
  final int? experienceYears;
  final double? rating;

  /// The earliest free start for the chosen service in the venue's wall-clock time.
  final DateTime? nextSlotAt;

  factory BeautyMaster.fromJson(Map<String, dynamic> json) => BeautyMaster(
        id: json['id'] as String,
        name: json['name'] as String,
        bio: json['bio'] as String? ?? '',
        specialty: json['specialty'] as String? ?? '',
        reviewCount: (json['reviewCount'] as num?)?.toInt() ?? 0,
        serviceIds: _strings(json['serviceIds']),
        experienceYears: (json['experienceYears'] as num?)?.toInt(),
        rating: _double(json['rating']),
        nextSlotAt: json['nextSlotAt'] == null
            ? null
            : parseVenueTime(json['nextSlotAt'] as String),
      );
}

class BeautyReview {
  const BeautyReview({
    required this.id,
    required this.authorName,
    required this.rating,
    required this.comment,
    this.masterName,
    this.serviceName,
  });

  final String id;
  final String authorName;
  final int rating;
  final String comment;
  final String? masterName;
  final String? serviceName;

  factory BeautyReview.fromJson(Map<String, dynamic> json) => BeautyReview(
        id: json['id'] as String,
        authorName: json['authorName'] as String? ?? '',
        rating: (json['rating'] as num).toInt(),
        comment: json['comment'] as String? ?? '',
        masterName: json['masterName'] as String?,
        serviceName: json['serviceName'] as String?,
      );
}

class BeautySalonDetail {
  const BeautySalonDetail({
    required this.salon,
    required this.description,
    required this.cancellationPolicy,
    required this.gallery,
    required this.services,
    required this.masters,
    required this.reviews,
    this.phone,
  });

  final BeautySalon salon;
  final String description;
  final String? phone;
  final String cancellationPolicy;
  final List<String> gallery;
  final List<BeautyService> services;
  final List<BeautyMaster> masters;
  final List<BeautyReview> reviews;

  factory BeautySalonDetail.fromJson(Map<String, dynamic> json) =>
      BeautySalonDetail(
        salon: BeautySalon.fromJson(json['salon'] as Map<String, dynamic>),
        description: json['description'] as String? ?? '',
        phone: json['phone'] as String?,
        cancellationPolicy: json['cancellationPolicy'] as String? ?? '',
        gallery: _strings(json['gallery']),
        services: [
          for (final item in json['services'] as List<dynamic>)
            BeautyService.fromJson(item as Map<String, dynamic>)
        ],
        masters: [
          for (final item in json['masters'] as List<dynamic>)
            BeautyMaster.fromJson(item as Map<String, dynamic>)
        ],
        reviews: [
          for (final item in json['reviews'] as List<dynamic>)
            BeautyReview.fromJson(item as Map<String, dynamic>)
        ],
      );
}

class BeautyServiceDetail {
  const BeautyServiceDetail({
    required this.service,
    required this.includes,
    required this.preparation,
    required this.cancellationPolicy,
    required this.gallery,
    required this.salon,
    required this.masters,
  });

  final BeautyService service;
  final List<String> includes;
  final String preparation;
  final String cancellationPolicy;
  final List<String> gallery;
  final BeautySalon salon;
  final List<BeautyMaster> masters;

  factory BeautyServiceDetail.fromJson(Map<String, dynamic> json) =>
      BeautyServiceDetail(
        service:
            BeautyService.fromJson(json['service'] as Map<String, dynamic>),
        includes: _strings(json['includes']),
        preparation: json['preparation'] as String? ?? '',
        cancellationPolicy: json['cancellationPolicy'] as String? ?? '',
        gallery: _strings(json['gallery']),
        salon: BeautySalon.fromJson(json['salon'] as Map<String, dynamic>),
        masters: [
          for (final item in json['masters'] as List<dynamic>)
            BeautyMaster.fromJson(item as Map<String, dynamic>)
        ],
      );
}

class BeautyPromotion {
  const BeautyPromotion({
    required this.id,
    required this.title,
    required this.percent,
    this.venueId,
  });

  final String id;
  final String title;
  final int percent;
  final String? venueId;

  factory BeautyPromotion.fromJson(Map<String, dynamic> json) =>
      BeautyPromotion(
        id: json['id'] as String,
        title: json['title'] as String,
        percent: (json['percent'] as num).toInt(),
        venueId: json['venueId'] as String?,
      );
}

class BeautyPromotions {
  const BeautyPromotions({required this.maxPercent, required this.items});

  /// Null when there is no active promotion: the banner is then not shown.
  final int? maxPercent;
  final List<BeautyPromotion> items;

  factory BeautyPromotions.fromJson(Map<String, dynamic> json) =>
      BeautyPromotions(
        maxPercent: (json['maxPercent'] as num?)?.toInt(),
        items: [
          for (final item in json['items'] as List<dynamic>)
            BeautyPromotion.fromJson(item as Map<String, dynamic>)
        ],
      );
}

/// Catalog filter chips of «Салоны красоты».
enum BeautyFilter {
  all('ALL'),
  nearby('NEARBY'),
  rating('RATING'),
  promo('PROMO');

  const BeautyFilter(this.code);
  final String code;
}

/// Server-side filters of the salon catalog.
class BeautySalonQuery {
  const BeautySalonQuery({
    this.filter = BeautyFilter.all,
    this.category,
    this.text = '',
    this.minPriceMinor,
    this.maxPriceMinor,
    this.maxDistanceMeters,
    this.verifiedOnly = false,
  });

  final BeautyFilter filter;
  final String? category;
  final String text;
  final int? minPriceMinor;
  final int? maxPriceMinor;
  final int? maxDistanceMeters;
  final bool verifiedOnly;

  BeautySalonQuery copyWith({
    BeautyFilter? filter,
    String? category,
    bool clearCategory = false,
    String? text,
    int? minPriceMinor,
    int? maxPriceMinor,
    bool clearPrice = false,
    int? maxDistanceMeters,
    bool clearDistance = false,
    bool? verifiedOnly,
  }) =>
      BeautySalonQuery(
        filter: filter ?? this.filter,
        category: clearCategory ? null : category ?? this.category,
        text: text ?? this.text,
        minPriceMinor: clearPrice ? null : minPriceMinor ?? this.minPriceMinor,
        maxPriceMinor: clearPrice ? null : maxPriceMinor ?? this.maxPriceMinor,
        maxDistanceMeters:
            clearDistance ? null : maxDistanceMeters ?? this.maxDistanceMeters,
        verifiedOnly: verifiedOnly ?? this.verifiedOnly,
      );

  bool get hasExtraFilters =>
      minPriceMinor != null ||
      maxPriceMinor != null ||
      maxDistanceMeters != null ||
      verifiedOnly;
}
