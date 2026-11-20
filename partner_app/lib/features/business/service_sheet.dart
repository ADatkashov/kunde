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

const healthCategoryCodes = [
  'DOCTORS',
  'CLINICS',
  'DENTISTRY',
  'DIAGNOSTICS',
  'LABS',
  'FITNESS',
  'SPA',
  'WELLNESS',
];

/// Create (when [service] is null) or edit a service: name, price (₸), duration, price kind, conditions.
/// Returns the saved service. Prices are sent in tiyn; the server validates every field again.
class ServiceSheet extends StatefulWidget {
  const ServiceSheet({
    required this.ops,
    required this.venueId,
    this.service,
    this.health = false,
    this.specialists = const [],
    super.key,
  });
  final PartnerOperations ops;
  final String venueId;
  final VenueService? service;
  final bool health;
  final List<Master> specialists;
  @override
  State<ServiceSheet> createState() => _ServiceSheetState();
}

class _ServiceSheetState extends State<ServiceSheet> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.service?.name);
  late final _price = TextEditingController(
    text: widget.service == null
        ? ''
        : (widget.service!.priceMinor ~/ 100).toString(),
  );
  late final _duration = TextEditingController(
    text: widget.service?.durationMinutes.toString() ?? '60',
  );
  late final _conditions = TextEditingController(
    text: widget.service?.conditions,
  );
  late String _kind = widget.service?.priceKind ?? 'FIXED';
  late String _category =
      widget.service?.autoCategory ?? (widget.health ? 'DOCTORS' : 'CAR_WASH');
  String? _masterId;
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
      final VenueService saved;
      if (widget.service case final existing?) {
        saved = await widget.ops.updateService(
          widget.venueId,
          existing.id,
          name: _name.text.trim(),
          priceMinor: price,
          durationMinutes: minutes,
          priceKind: widget.health ? null : _kind,
          conditions: widget.health ? null : _conditions.text.trim(),
        );
      } else if (widget.health) {
        saved = await widget.ops.createHealthService(
          widget.venueId,
          name: _name.text.trim(),
          category: _category,
          masterId: _masterId!,
          priceMinor: price,
          durationMinutes: minutes,
        );
      } else {
        saved = await widget.ops.createService(
          widget.venueId,
          name: _name.text.trim(),
          autoCategory: _category,
          priceMinor: price,
          durationMinutes: minutes,
          priceKind: _kind,
          conditions: _conditions.text.trim(),
        );
      }
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
      padding: EdgeInsets.fromLTRB(
        Gap.lg,
        Gap.lg,
        Gap.lg,
        MediaQuery.viewInsetsOf(context).bottom + Gap.lg,
      ),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.service == null ? s.addService : s.editService,
                style: context.text.titleMedium,
              ),
              TextFormField(
                controller: _name,
                maxLength: 120,
                decoration: InputDecoration(labelText: s.dishName),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? s.dishNameInvalid : null,
              ),
              if (widget.service == null)
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _category,
                  decoration: InputDecoration(labelText: s.serviceCategory),
                  items: [
                    for (final c
                        in widget.health
                            ? healthCategoryCodes
                            : autoCategoryCodes)
                      DropdownMenuItem(
                        value: c,
                        child: Text(
                          widget.health
                              ? s.healthDirection(c)
                              : s.autoCategory(c),
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _category = v ?? _category),
                ),
              if (widget.health && widget.service == null)
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: s.healthSelectSpecialist,
                  ),
                  items: [
                    for (final specialist in widget.specialists)
                      DropdownMenuItem(
                        value: specialist.id,
                        child: Text(specialist.name),
                      ),
                  ],
                  validator: (value) =>
                      value == null ? s.healthSelectSpecialist : null,
                  onChanged: (value) => setState(() => _masterId = value),
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
                },
              ),
              TextFormField(
                controller: _duration,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: s.serviceDuration),
                validator: (v) {
                  final n = int.tryParse((v ?? '').trim());
                  return n == null || n < 15 || n > 240 || n % 15 != 0
                      ? s.serviceDurationInvalid
                      : null;
                },
              ),
              if (!widget.health) ...[
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
                  decoration: InputDecoration(labelText: s.serviceConditions),
                ),
                Text(s.autoCategoriesNote, style: context.text.bodySmall),
              ],
              const SizedBox(height: Gap.md),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(s.save),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
