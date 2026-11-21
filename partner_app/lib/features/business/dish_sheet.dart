import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/error_text.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/partner_operations.dart';
import 'product_card_page.dart';

/// Parses a price typed in tenge ("1500", "1 500", "1500,50") to minor units.
/// Returns null when invalid or outside 0 … 1 000 000 ₸.
int? parsePriceMinor(String input) {
  final t = input.trim().replaceAll(RegExp(r'\s'), '').replaceAll(',', '.');
  if (!RegExp(r'^\d{1,7}(\.\d{1,2})?$').hasMatch(t)) return null;
  final parts = t.split('.');
  final whole = int.parse(parts[0]);
  final cents = parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0'));
  final minor = whole * 100 + cents;
  return minor <= 100000000 ? minor : null;
}

/// Add (dish == null) or edit a dish. Returns true when something was saved.
Future<bool?> showDishSheet(
  BuildContext context, {
  required PartnerOperations ops,
  required String restaurantId,
  required Dish? dish,
  required Map<String, String> sections,
}) =>
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DishSheet(
        ops: ops,
        restaurantId: restaurantId,
        dish: dish,
        sections: sections,
      ),
    );

class _DishSheet extends StatefulWidget {
  const _DishSheet({
    required this.ops,
    required this.restaurantId,
    required this.dish,
    required this.sections,
  });
  final PartnerOperations ops;
  final String restaurantId;
  final Dish? dish;
  final Map<String, String> sections;
  @override
  State<_DishSheet> createState() => _DishSheetState();
}

class _DishSheetState extends State<_DishSheet> {
  late final _name = TextEditingController(text: widget.dish?.name ?? '');
  late final _desc =
      TextEditingController(text: widget.dish?.description ?? '');
  late final _price = TextEditingController(
      text: widget.dish == null ? '' : _plain(widget.dish!.priceMinor));
  late final _stock =
      TextEditingController(text: widget.dish?.stockQty?.toString() ?? '');
  String _unit = 'PIECE';
  late String? _section =
      widget.dish?.sectionId ?? widget.sections.keys.firstOrNull;
  bool _busy = false;
  String? _error;

  static String _plain(int minor) => minor % 100 == 0
      ? '${minor ~/ 100}'
      : (minor / 100).toStringAsFixed(2).replaceAll('.', ',');

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _price.dispose();
    _stock.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = S.of(context);
    if (_busy) return;
    final name = _name.text.trim();
    final price = parsePriceMinor(_price.text);
    final stockText = _stock.text.trim();
    final stock = stockText.isEmpty ? null : int.tryParse(stockText);
    if (name.length < 2 || name.length > 160) {
      setState(() => _error = s.dishNameInvalid);
      return;
    }
    if (price == null) {
      setState(() => _error = s.dishPriceInvalid);
      return;
    }
    if (stockText.isNotEmpty &&
        (stock == null || stock < 0 || stock > 100000)) {
      setState(() => _error = s.dishStockInvalid);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final d = widget.dish;
      if (d == null) {
        if (_section == null) {
          setState(() => _error = s.dishNoSection);
          return;
        }
        await widget.ops.createDish(widget.restaurantId,
            sectionId: _section!,
            name: name,
            description: _desc.text.trim(),
            priceMinor: price,
            unit: _unit);
      } else {
        final desc = _desc.text.trim();
        await widget.ops.updateDish(
          widget.restaurantId,
          d.id,
          name: name != d.name ? name : null,
          description: desc != (d.description ?? '') ? desc : null,
          priceMinor: price != d.priceMinor ? price : null,
          stockQty: stock != null && stock != d.stockQty ? stock : null,
          clearStock: stock == null && d.stockQty != null,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on Object catch (e) {
      if (mounted) setState(() => _error = errorText(s, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          Gap.lg, 0, Gap.lg, MediaQuery.viewInsetsOf(context).bottom + Gap.lg),
      child: SingleChildScrollView(
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.dish == null ? s.addDish : s.editDish,
                  style: context.text.titleLarge),
              const SizedBox(height: Gap.lg),
              if (widget.dish == null && widget.sections.length > 1) ...[
                DropdownButtonFormField<String>(
                  initialValue: _section,
                  decoration: InputDecoration(labelText: s.dishSection),
                  items: [
                    for (final e in widget.sections.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setState(() => _section = v),
                ),
                const SizedBox(height: Gap.md),
              ],
              TextField(
                controller: _name,
                maxLength: 160,
                textCapitalization: TextCapitalization.sentences,
                decoration:
                    InputDecoration(labelText: s.dishName, counterText: ''),
              ),
              const SizedBox(height: Gap.md),
              TextField(
                controller: _desc,
                maxLength: 500,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                    labelText: s.dishDescription, counterText: ''),
              ),
              const SizedBox(height: Gap.md),
              if (widget.dish == null) ...[
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'PIECE', label: Text(s.dishUnitPiece)),
                    ButtonSegment(value: 'KG', label: Text(s.dishUnitKg)),
                  ],
                  selected: {_unit},
                  onSelectionChanged: (v) => setState(() => _unit = v.first),
                ),
                const SizedBox(height: Gap.md),
              ],
              TextField(
                controller: _price,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9 ,.]'))
                ],
                decoration: InputDecoration(labelText: s.dishPrice),
              ),
              if (widget.dish != null) ...[
                const SizedBox(height: Gap.md),
                TextField(
                  controller: _stock,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                      labelText: widget.dish!.weighed
                          ? s.dishStockGrams
                          : s.dishStock),
                ),
              ],
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
              if (widget.dish != null) ...[
                const SizedBox(height: Gap.md),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () async {
                          final changed = await Navigator.of(context)
                              .push<bool>(MaterialPageRoute(
                                  builder: (_) => ProductCardPage(
                                      ops: widget.ops,
                                      restaurantId: widget.restaurantId,
                                      dish: widget.dish!)));
                          if (changed == true && context.mounted) {
                            Navigator.pop(context, true);
                          }
                        },
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: Text(s.productCard),
                ),
              ],
              const SizedBox(height: Gap.lg),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(_busy ? s.pleaseWait : s.save),
              ),
            ]),
      ),
    );
  }
}
