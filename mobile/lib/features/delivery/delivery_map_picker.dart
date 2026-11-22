import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:kunde_maps_sdk/kunde_maps_sdk.dart';

import '../rides/ride_api.dart';
import 'delivery_strings.dart';

class DeliveryMapPicker extends StatefulWidget {
  const DeliveryMapPicker({required this.isPickup, this.initial, super.key});

  final bool isPickup;
  final RideAddress? initial;

  @override
  State<DeliveryMapPicker> createState() => _DeliveryMapPickerState();
}

class _DeliveryMapPickerState extends State<DeliveryMapPicker> {
  final _http = http.Client();

  @override
  void dispose() {
    _http.close();
    super.dispose();
  }

  Future<void> _confirm(PickedLocation selection, DeliveryStrings s) async {
    final point = selection.point;
    final address = selection.label(s.language)?.trim();
    final String? label = address != null && address.isNotEmpty
        ? address
        : await showDialog<String>(
            context: context,
            builder: (_) => _PinAddressDialog(isPickup: widget.isPickup),
          );
    if (!mounted || label == null) return;
    Navigator.pop(
      context,
      RideAddress(label, {
        'latitude': point.lat,
        'longitude': point.lon,
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = DeliveryStrings(context);
    final config = MapsConfig.fromEnvironment(language: s.language);
    final initial = widget.initial?.point;
    return Scaffold(
      appBar: AppBar(title: Text(widget.isPickup ? s.pickup : s.destination)),
      body: LocationPicker(
        initial: initial == null
            ? null
            : GeoPoint.parse(initial['latitude'], initial['longitude']),
        config: config,
        search: PlaceSearch(MapsClient(config, _http)),
        dark: Theme.of(context).brightness == Brightness.dark,
        onPicked: (point) => _confirm(point, s),
      ),
    );
  }
}

class _PinAddressDialog extends StatefulWidget {
  const _PinAddressDialog({required this.isPickup});

  final bool isPickup;

  @override
  State<_PinAddressDialog> createState() => _PinAddressDialogState();
}

class _PinAddressDialogState extends State<_PinAddressDialog> {
  final _form = GlobalKey<FormState>();
  final _address = TextEditingController();

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  void _submit() {
    if (_form.currentState?.validate() == true) {
      Navigator.pop(context, _address.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = DeliveryStrings(context);
    return AlertDialog(
      scrollable: true,
      title: Text(widget.isPickup ? s.pickup : s.destination),
      content: Form(
        key: _form,
        child: TextFormField(
          controller: _address,
          autofocus: true,
          maxLength: 240,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: s.t('Улица и номер дома', 'Көше және үй нөмірі',
                'Street and house number'),
          ),
          onFieldSubmitted: (_) => _submit(),
          validator: (value) =>
              value == null || value.trim().isEmpty ? s.required : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(s.t('Выбрать адрес', 'Мекенжайды таңдау', 'Use address')),
        ),
      ],
    );
  }
}
