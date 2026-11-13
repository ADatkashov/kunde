/// A published offering from `GET /search/offerings`. Carries no price, partner
/// or availability: the server does not expose them yet.
class CatalogOffering {
  const CatalogOffering({
    required this.id,
    required this.categoryId,
    required this.kind,
    required this.nameRu,
    required this.nameKk,
    this.nameEn,
  });

  final String id;
  final String categoryId;
  final String kind;
  final String nameRu;
  final String nameKk;
  final String? nameEn;

  factory CatalogOffering.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final categoryId = json['categoryId'];
    final kind = json['kind'];
    final nameRu = json['nameRu'];
    final nameKk = json['nameKk'];
    final nameEn = json['nameEn'];
    if (id is! String ||
        categoryId is! String ||
        kind is! String ||
        nameRu is! String ||
        nameKk is! String ||
        (nameEn != null && nameEn is! String)) {
      throw const FormatException('Invalid catalog offering response');
    }
    return CatalogOffering(
        id: id,
        categoryId: categoryId,
        kind: kind,
        nameRu: nameRu,
        nameKk: nameKk,
        nameEn: nameEn as String?);
  }

  String localizedName(String languageCode) => switch (languageCode) {
        'kk' => nameKk,
        'en' => nameEn ?? nameRu,
        _ => nameRu,
      };
}
