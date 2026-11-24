class CatalogCategory {
  const CatalogCategory(
      {required this.id, required this.nameRu, required this.nameKk});

  final String id;
  final String nameRu;
  final String nameKk;

  factory CatalogCategory.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final nameRu = json['nameRu'];
    final nameKk = json['nameKk'];
    if (id is! String || nameRu is! String || nameKk is! String) {
      throw const FormatException('Invalid catalog category response');
    }
    return CatalogCategory(id: id, nameRu: nameRu, nameKk: nameKk);
  }

  String localizedName(String languageCode) =>
      languageCode == 'kk' ? nameKk : nameRu;
}
