import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/error_text.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/partner_operations.dart';
import 'dish_sheet.dart' show parsePriceMinor;

/// Parses a decimal typed with a comma or a dot; null when empty, invalid or outside [0, max].
double? parseBounded(String input, double max) {
  final t = input.trim().replaceAll(',', '.');
  final v = double.tryParse(t);
  return v == null || v < 0 || v > max ? null : v;
}

/// Groceries product card of one dish: category, brand, origin, composition, storage, nutrition, the price before a
/// discount and up to six photos (HTTPS links). Owner/Manager only; the server enforces the role and the rules.
class ProductCardPage extends StatefulWidget {
  const ProductCardPage(
      {required this.ops,
      required this.restaurantId,
      required this.dish,
      super.key});

  final PartnerOperations ops;
  final String restaurantId;
  final Dish dish;

  @override
  State<ProductCardPage> createState() => _ProductCardPageState();
}

class _ProductCardPageState extends State<ProductCardPage> {
  late Dish _dish = widget.dish;
  late String? _category = _dish.groceryCategory;
  late final _brand = TextEditingController(text: _dish.brand ?? '');
  late final _origin = TextEditingController(text: _dish.originCountry ?? '');
  late final _composition =
      TextEditingController(text: _dish.composition ?? '');
  late final _storage =
      TextEditingController(text: _dish.storageConditions ?? '');
  late final _kcal = TextEditingController(text: _dish.kcal?.toString() ?? '');
  late final _protein = TextEditingController(text: _fmt(_dish.protein));
  late final _fat = TextEditingController(text: _fmt(_dish.fat));
  late final _carbs = TextEditingController(text: _fmt(_dish.carbs));
  late final _oldPrice = TextEditingController(
      text: _dish.compareAtPriceMinor == null
          ? ''
          : _plain(_dish.compareAtPriceMinor!));
  final _photo = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _saved = false;

  static String _fmt(double? v) =>
      v == null ? '' : v.toString().replaceAll('.', ',');
  static String _plain(int minor) => minor % 100 == 0
      ? '${minor ~/ 100}'
      : (minor / 100).toStringAsFixed(2).replaceAll('.', ',');

  @override
  void dispose() {
    for (final c in [
      _brand,
      _origin,
      _composition,
      _storage,
      _kcal,
      _protein,
      _fat,
      _carbs,
      _oldPrice,
      _photo
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final s = S.of(context);
    if (_busy) return;
    final kcalText = _kcal.text.trim();
    final kcal = kcalText.isEmpty ? null : int.tryParse(kcalText);
    final protein =
        _protein.text.trim().isEmpty ? null : parseBounded(_protein.text, 100);
    final fat = _fat.text.trim().isEmpty ? null : parseBounded(_fat.text, 100);
    final carbs =
        _carbs.text.trim().isEmpty ? null : parseBounded(_carbs.text, 100);
    final invalidNutrition =
        (kcalText.isNotEmpty && (kcal == null || kcal < 0 || kcal > 1000)) ||
            (_protein.text.trim().isNotEmpty && protein == null) ||
            (_fat.text.trim().isNotEmpty && fat == null) ||
            (_carbs.text.trim().isNotEmpty && carbs == null);
    if (invalidNutrition) {
      setState(() => _error = s.productNutritionInvalid);
      return;
    }
    final oldText = _oldPrice.text.trim();
    final old = oldText.isEmpty ? null : parsePriceMinor(oldText);
    if (oldText.isNotEmpty && (old == null || old <= _dish.priceMinor)) {
      setState(() => _error = s.productOldPriceInvalid);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    String? changed(String text, String? before) =>
        text.trim() != (before ?? '') ? text.trim() : null;
    try {
      final d = await widget.ops.updateProduct(
        widget.restaurantId,
        _dish.id,
        groceryCategory: _category != _dish.groceryCategory ? _category : null,
        clearCategory: _category == null && _dish.groceryCategory != null,
        brand: changed(_brand.text, _dish.brand),
        originCountry: changed(_origin.text, _dish.originCountry),
        composition: changed(_composition.text, _dish.composition),
        storageConditions: changed(_storage.text, _dish.storageConditions),
        kcal: kcal != _dish.kcal ? kcal : null,
        protein: protein != _dish.protein ? protein : null,
        fat: fat != _dish.fat ? fat : null,
        carbs: carbs != _dish.carbs ? carbs : null,
        compareAtPriceMinor:
            old != null && old != _dish.compareAtPriceMinor ? old : null,
        clearCompareAt: old == null && _dish.compareAtPriceMinor != null,
      );
      if (!mounted) return;
      setState(() {
        _dish = d;
        _saved = true;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.productSaved)));
    } on Object catch (e) {
      if (mounted) setState(() => _error = errorText(s, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addPhoto() async {
    final s = S.of(context);
    final url = _photo.text.trim();
    if (!RegExp(r'^https://\S{4,480}$').hasMatch(url)) {
      setState(() => _error = s.productPhotoInvalid);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final d = await widget.ops.addPhoto(widget.restaurantId, _dish.id, url);
      if (mounted) {
        _photo.clear();
        setState(() {
          _dish = d;
          _saved = true;
        });
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = errorText(s, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removePhoto(DishPhoto photo) async {
    final s = S.of(context);
    setState(() => _busy = true);
    try {
      final d =
          await widget.ops.removePhoto(widget.restaurantId, _dish.id, photo.id);
      if (mounted) {
        setState(() {
          _dish = d;
          _saved = true;
        });
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = errorText(s, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    Widget gap() => const SizedBox(height: Gap.md);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _saved);
      },
      child: Scaffold(
        appBar: AppBar(title: Text('${s.productCard} · ${_dish.name}')),
        body: ListView(
          padding: const EdgeInsets.all(Gap.lg),
          children: [
            DropdownButtonFormField<String?>(
              initialValue: _category,
              isExpanded: true,
              decoration: InputDecoration(labelText: s.productCategory),
              items: [
                DropdownMenuItem<String?>(
                    value: null, child: Text(s.productNoCategory)),
                for (final slug in S.productCategories)
                  DropdownMenuItem<String?>(
                      value: slug, child: Text(s.productCategoryName(slug))),
              ],
              onChanged: (v) => setState(() => _category = v),
            ),
            gap(),
            TextField(
                controller: _brand,
                maxLength: 80,
                decoration: InputDecoration(
                    labelText: s.productBrand, counterText: '')),
            gap(),
            TextField(
                controller: _origin,
                maxLength: 60,
                decoration: InputDecoration(
                    labelText: s.productOrigin, counterText: '')),
            gap(),
            TextField(
                controller: _composition,
                maxLength: 500,
                maxLines: 2,
                decoration: InputDecoration(
                    labelText: s.productComposition, counterText: '')),
            gap(),
            TextField(
                controller: _storage,
                maxLength: 300,
                decoration: InputDecoration(
                    labelText: s.productStorage, counterText: '')),
            gap(),
            Text(s.productNutrition, style: context.text.titleSmall),
            gap(),
            Wrap(spacing: Gap.md, runSpacing: Gap.md, children: [
              for (final (c, label, int) in [
                (_kcal, s.productKcal, true),
                (_protein, s.productProtein, false),
                (_fat, s.productFat, false),
                (_carbs, s.productCarbs, false),
              ])
                SizedBox(
                  width: 150,
                  child: TextField(
                    controller: c,
                    keyboardType:
                        TextInputType.numberWithOptions(decimal: !int),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(int ? r'[0-9]' : r'[0-9,.]'))
                    ],
                    decoration: InputDecoration(labelText: label),
                  ),
                ),
            ]),
            gap(),
            TextField(
              controller: _oldPrice,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9 ,.]'))
              ],
              decoration: InputDecoration(labelText: s.productOldPrice),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: Gap.md),
                child: Semantics(
                  liveRegion: true,
                  child: Text(_error!,
                      style: context.text.bodyMedium
                          ?.copyWith(color: context.colors.error)),
                ),
              ),
            gap(),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? s.pleaseWait : s.save),
            ),
            const Divider(height: Gap.xl),
            Text(s.productPhotos, style: context.text.titleSmall),
            const SizedBox(height: Gap.sm),
            Text(s.productPhotoHint, style: context.text.bodySmall),
            gap(),
            for (final p in _dish.photos)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: Image.network(p.url,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.image_not_supported_outlined)),
                  ),
                ),
                title:
                    Text(p.url, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  tooltip: s.productRemovePhoto,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _busy ? null : () => _removePhoto(p),
                ),
              ),
            if (_dish.photos.length < 6) ...[
              TextField(
                controller: _photo,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(labelText: s.productPhotoUrl),
              ),
              const SizedBox(height: Gap.sm),
              OutlinedButton.icon(
                onPressed: _busy ? null : _addPhoto,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(s.productPhotoAdd),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
