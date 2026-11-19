import 'package:flutter/material.dart';

import '../auto_services.dart';
import '../data/auto_api.dart';
import '../data/auto_models.dart';
import 'auto_strings.dart';
import 'auto_widgets.dart';

/// My cars: list, add, edit and archive (several cars; plate is optional).
class VehiclesScreen extends StatefulWidget {
  const VehiclesScreen({required this.services, super.key});

  final AutoServices services;

  @override
  State<VehiclesScreen> createState() => _VehiclesScreenState();
}

class _VehiclesScreenState extends State<VehiclesScreen> {
  late Future<List<Vehicle>> _vehicles = widget.services.api.vehicles();

  void _reload() => setState(() {
        _vehicles = widget.services.api.vehicles();
      });

  Future<void> _open([Vehicle? v]) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) =>
            VehicleFormScreen(services: widget.services, vehicle: v)));
    if (saved == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final s = auL10n(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.auMyVehicles)),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _open(),
          icon: const Icon(Icons.add_rounded),
          label: Text(s.auAddVehicle)),
      body: FutureBuilder<List<Vehicle>>(
        future: _vehicles,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const AutoStateView.loading();
          }
          if (snap.hasError) {
            final f = snap.error is AutoException
                ? (snap.error as AutoException).failure
                : AutoFailure.other;
            return AutoStateView.error(error: f, onRetry: _reload);
          }
          final list = snap.data!;
          if (list.isEmpty) {
            return AutoStateView.empty(
                emptyTitle: s.auNoVehicles, emptyBody: s.auNoVehiclesBody);
          }
          return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                for (final v in list)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.directions_car_rounded),
                      title: Text('${v.make} ${v.model}'),
                      subtitle: Text(
                          '${v.year}${v.plate == null ? '' : ' · ${v.plate}'}'),
                      trailing: const Icon(Icons.edit_rounded),
                      onTap: () => _open(v),
                    ),
                  ),
              ]);
        },
      ),
    );
  }
}

class VehicleFormScreen extends StatefulWidget {
  const VehicleFormScreen({required this.services, this.vehicle, super.key});

  final AutoServices services;
  final Vehicle? vehicle;

  @override
  State<VehicleFormScreen> createState() => _VehicleFormScreenState();
}

class _VehicleFormScreenState extends State<VehicleFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _make = TextEditingController(text: widget.vehicle?.make);
  late final _model = TextEditingController(text: widget.vehicle?.model);
  late final _year =
      TextEditingController(text: widget.vehicle?.year.toString());
  late final _plate = TextEditingController(text: widget.vehicle?.plate);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _make.dispose();
    _model.dispose();
    _year.dispose();
    _plate.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final s = auL10n(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.services.api.saveVehicle(
          id: widget.vehicle?.id,
          version: widget.vehicle?.version,
          make: _make.text,
          model: _model.text,
          year: int.parse(_year.text.trim()),
          plate: _plate.text);
      if (mounted) Navigator.of(context).pop(true);
    } on AutoException catch (e) {
      if (mounted) {
        setState(() {
          _error = s.auError(e.failure);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _delete() async {
    final s = auL10n(context);
    final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
              content: Text(s.auDeleteQuestion),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: Text(s.auCancelAction)),
                FilledButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: Text(s.auDelete)),
              ],
            ));
    if (ok != true) return;
    setState(() {
      _busy = true;
    });
    try {
      await widget.services.api.deleteVehicle(widget.vehicle!.id);
      if (mounted) Navigator.of(context).pop(true);
    } on AutoException catch (e) {
      if (mounted) {
        setState(() {
          _error = s.auError(e.failure);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = auL10n(context);
    String? required(String? v) =>
        v == null || v.trim().isEmpty ? s.auFieldRequired : null;
    return Scaffold(
      appBar: AppBar(
          title:
              Text(widget.vehicle == null ? s.auAddVehicle : s.auEditVehicle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Form(
            key: _form,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              TextFormField(
                  controller: _make,
                  maxLength: 40,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: s.auMake),
                  validator: required),
              TextFormField(
                  controller: _model,
                  maxLength: 40,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: s.auModel),
                  validator: required),
              TextFormField(
                  controller: _year,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: s.auYear),
                  validator: (v) {
                    final y = int.tryParse((v ?? '').trim());
                    return y == null || y < 1950 || y > DateTime.now().year + 1
                        ? s.auYearInvalid
                        : null;
                  }),
              TextFormField(
                  controller: _plate,
                  maxLength: 16,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(labelText: s.auPlate),
                  validator: (v) {
                    final t = (v ?? '').replaceAll(RegExp(r'[\s-]'), '');
                    return t.isEmpty ||
                            RegExp(r'^[A-Za-z0-9]{3,12}$').hasMatch(t)
                        ? null
                        : s.auPlateInvalid;
                  }),
              if (_error != null) ...[
                const SizedBox(height: 8),
                AutoErrorBanner(_error!),
              ],
              const SizedBox(height: 16),
              FilledButton(
                  onPressed: _busy ? null : _save, child: Text(s.auSave)),
              if (widget.vehicle != null) ...[
                const SizedBox(height: 8),
                TextButton(
                    onPressed: _busy ? null : _delete, child: Text(s.auDelete)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
