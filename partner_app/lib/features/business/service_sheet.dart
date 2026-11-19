import 'package:flutter/material.dart';

import '../../core/error_text.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/partner_operations.dart';
import '../../widgets/dialogs.dart';

const autoCategoryCodes = [
  'CAR_WASH',
  'TIRE',
  'OIL_CHANGE',
  'DIAGNOSTICS',
  'MAINTENANCE',
  'REPAIR',
  'ROADSIDE',
  'OTHER',
];

/// Create (when [service] is null) or edit a service: name, price (₸), duration, price kind, conditions.
/// Returns the saved service. Prices are sent in tiyn; the server validates every field again.
class ServiceSheet extends StatefulWidget {
  const ServiceSheet(
      {required this.ops, required this.venueId, this.service, super.key});
  final PartnerOperations ops;
  final String venueId;
  final VenueService? service;
  @override
  State<ServiceSheet> createState() => _ServiceSheetState();
}

class _ServiceSheetState extends State<ServiceSheet> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.service?.name);
  late final _price = TextEditingController(
      text: widget.service == null
          ? ''
          : (widget.service!.priceMinor ~/ 100).toString());
  late final _duration = TextEditingController(
      text: widget.service?.durationMinutes.toString() ?? '60');
  late final _conditions =
      TextEditingController(text: widget.service?.conditions);
  late String _kind = widget.service?.priceKind ?? 'FIXED';
  late String _category = widget.service?.autoCategory ?? 'CAR_WASH';
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _duration.dispose();
    _conditions.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final s = S.of(context);
    setState(() => _busy = true);
    try {
      final price = int.parse(_price.text.trim()) * 100;
      final minutes = int.parse(_duration.text.trim());
      final saved = widget.service == null
          ? await widget.ops.createService(widget.venueId,
              name: _name.text.trim(),
              autoCategory: _category,
              priceMinor: price,
              durationMinutes: minutes,
              priceKind: _kind,
              conditions: _conditions.text.trim())
          : await widget.ops.updateService(widget.venueId, widget.service!.id,
              name: _name.text.trim(),
              priceMinor: price,
              durationMinutes: minutes,
              priceKind: _kind,
              conditions: _conditions.text.trim());
      if (mounted) Navigator.pop(context, saved);
    } on Object catch (e) {
      if (mounted) showToast(context, errorText(s, e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg,
          MediaQuery.viewInsetsOf(context).bottom + Gap.lg),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(widget.service == null ? s.addService : s.editService,
                style: context.text.titleMedium),
            TextFormField(
                controller: _name,
                maxLength: 120,
                decoration: InputDecoration(labelText: s.dishName),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? s.dishNameInvalid : null),
            if (widget.service == null)
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _category,
                decoration: InputDecoration(labelText: s.serviceCategory),
                items: [
                  for (final c in autoCategoryCodes)
                    DropdownMenuItem(value: c, child: Text(s.autoCategory(c))),
                ],
                onChanged: (v) => setState(() => _category = v ?? _category),
              ),
            TextFormField(
                controller: _price,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: s.dishPrice),
                validator: (v) {
                  final n = int.tryParse((v ?? '').trim());
                  return n == null || n < 0 || n > 1000000
                      ? s.dishPriceInvalid
                      : null;
                }),
            TextFormField(
                controller: _duration,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: s.serviceDuration),
                validator: (v) {
                  final n = int.tryParse((v ?? '').trim());
                  return n == null || n < 15 || n > 240 || n % 15 != 0
                      ? s.serviceDurationInvalid
                      : null;
                }),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _kind,
              decoration: InputDecoration(labelText: s.priceKindLabel),
              items: [
                for (final k in const ['FIXED', 'FROM', 'DIAGNOSTIC'])
                  DropdownMenuItem(value: k, child: Text(s.priceKind(k))),
              ],
              onChanged: (v) => setState(() => _kind = v ?? _kind),
            ),
            TextFormField(
                controller: _conditions,
                maxLength: 300,
                decoration: InputDecoration(labelText: s.serviceConditions)),
            Text(s.autoCategoriesNote, style: context.text.bodySmall),
            const SizedBox(height: Gap.md),
            FilledButton(onPressed: _busy ? null : _save, child: Text(s.save)),
          ]),
        ),
      ),
    );
  }
}
