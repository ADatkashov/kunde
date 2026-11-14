/// A published offering from `GET /search/offerings`. Carries the approved
/// partner's display name, the single final KZT price (minor units, D-04 DEV pilot)
/// and the availability flag when the server sends them; no fees are added client-side.
class CatalogOffering {
  const CatalogOffering({
    required this.id,
    required this.categoryId,
    required this.kind,
    required this.nameRu,
    required this.nameKk,
    this.nameEn,
    this.partnerName,
    this.priceMinor,
    this.currency,
    this.available = true,
  });

  final String id;
  final String categoryId;
  final String kind;
  final String nameRu;
  final String nameKk;
  final String? nameEn;
  final String? partnerName;
  final int? priceMinor;
  final String? currency;
  final bool available;

  factory CatalogOffering.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final categoryId = json['categoryId'];
    final kind = json['kind'];
    final nameRu = json['nameRu'];
    final nameKk = json['nameKk'];
    final nameEn = json['nameEn'];
    final partnerName = json['partnerName'];
    final priceMinor = json['priceMinor'];
    final currency = json['currency'];
    final available = json['available'];
    if (id is! String ||
        categoryId is! String ||
        kind is! String ||
        nameRu is! String ||
        nameKk is! String ||
        (nameEn != null && nameEn is! String) ||
        (partnerName != null && partnerName is! String) ||
        (priceMinor != null && priceMinor is! int) ||
        (currency != null && currency is! String) ||
        (available != null && available is! bool)) {
      throw const FormatException('Invalid catalog offering response');
    }
    return CatalogOffering(
        id: id,
        categoryId: categoryId,
        kind: kind,
        nameRu: nameRu,
        nameKk: nameKk,
        nameEn: nameEn as String?,
        partnerName: partnerName as String?,
        priceMinor: priceMinor as int?,
        currency: currency as String?,
        available: available as bool? ?? true);
  }

  String localizedName(String languageCode) => switch (languageCode) {
        'kk' => nameKk,
        'en' => nameEn ?? nameRu,
        _ => nameRu,
      };
}
