import 'package:flutter/material.dart';
import 'auth_repository.dart';

class AddressPanel extends StatefulWidget {
  const AddressPanel({required this.auth, super.key});
  final AuthRepository auth;

  @override
  State<AddressPanel> createState() => _AddressPanelState();
}

class _AddressPanelState extends State<AddressPanel> {
  late Future<List<Map<String, dynamic>>> _addresses;
  bool _busy = false;
  final _label = TextEditingController();
  final _address = TextEditingController();
  final _latitude = TextEditingController();
  final _longitude = TextEditingController();
  final _form = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() => _addresses = widget.auth.addresses();

  String _t(String ru, String kk, String en) {
    final lang = Localizations.localeOf(context).languageCode;
    return lang == 'kk' ? kk : lang == 'en' ? en : ru;
  }

  void _error() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_t('Не удалось выполнить действие. Повторите попытку.',
            'Әрекет орындалмады. Қайталап көріңіз.',
            'Action failed. Please try again.'))));
  }

  Future<void> _create() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await widget.auth.createAddress(
        label: _label.text,
        formattedAddress: _address.text,
        latitude: double.parse(_latitude.text),
        longitude: double.parse(_longitude.text),
      );
      if (!mounted) return;
      _label.clear();
      _address.clear();
      _latitude.clear();
      _longitude.clear();
      setState(_refresh);
    } catch (_) {
      _error();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('Удалить адрес?', 'Мекенжайды жою керек пе?',
            'Delete address?')),
        content: Text(item['formattedAddress'] as String),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_t('Отмена', 'Бас тарту', 'Cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(_t('Удалить', 'Жою', 'Delete'))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.auth.deleteAddress(
          item['id'] as String, item['version'] as int);
      if (mounted) setState(_refresh);
    } on IdentityApiError catch (error) {
      _error();
      if (error.status == 409 && mounted) setState(_refresh);
    } catch (_) {
      _error();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_t('Мои адреса', 'Менің мекенжайларым', 'My addresses'),
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(_t(
              'Доступность доставки проверяется отдельно. Координаты вводятся вручную.',
              'Жеткізу қолжетімділігі бөлек тексеріледі. Координаттар қолмен енгізіледі.',
              'Delivery availability is checked separately. Enter coordinates manually.')),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _addresses,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const LinearProgressIndicator();
              }
              if (snapshot.hasError) {
                return TextButton(
                  onPressed: () => setState(_refresh),
                  child: Text(_t('Повторить загрузку', 'Қайта жүктеу', 'Retry')),
                );
              }
              final items = snapshot.data ?? [];
              return Column(children: [
                for (final item in items)
                  ListTile(
                    title: Text(item['label'] as String),
                    subtitle: Text(
                        '${item['formattedAddress']} · ${item['serviceable'] == true ? _t('Зона обслуживания подтверждена', 'Қызмет көрсету аймағы расталған', 'Serviceable zone confirmed') : _t('Зона обслуживания не подтверждена', 'Қызмет көрсету аймағы расталмаған', 'Serviceability not confirmed')}'),
                    trailing: IconButton(
                      tooltip: _t('Удалить', 'Жою', 'Delete'),
                      onPressed: _busy ? null : () => _delete(item),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
              ]);
            },
          ),
          const SizedBox(height: 12),
          Form(
            key: _form,
            child: Column(children: [
              TextFormField(
                controller: _label,
                maxLength: 80,
                decoration: InputDecoration(
                    labelText: _t('Название', 'Атауы', 'Label')),
                validator: (v) => v == null || v.trim().isEmpty
                    ? _t('Обязательное поле', 'Міндетті өріс', 'Required')
                    : null,
              ),
              TextFormField(
                controller: _address,
                maxLength: 500,
                decoration: InputDecoration(
                    labelText: _t('Адрес', 'Мекенжай', 'Address')),
                validator: (v) => v == null || v.trim().isEmpty
                    ? _t('Обязательное поле', 'Міндетті өріс', 'Required')
                    : null,
              ),
              Row(children: [
                Expanded(
                    child: TextFormField(
                  controller: _latitude,
                  keyboardType: const TextInputType.numberWithOptions(
                      signed: true, decimal: true),
                  decoration: InputDecoration(
                      labelText: _t('Широта', 'Ендік', 'Latitude')),
                  validator: (v) {
                    final n = double.tryParse(v ?? '');
                    return n == null || !n.isFinite || n < -90 || n > 90
                        ? _t('Неверная широта', 'Қате ендік', 'Invalid latitude')
                        : null;
                  },
                )),
                const SizedBox(width: 12),
                Expanded(
                    child: TextFormField(
                  controller: _longitude,
                  keyboardType: const TextInputType.numberWithOptions(
                      signed: true, decimal: true),
                  decoration: InputDecoration(
                      labelText: _t('Долгота', 'Бойлық', 'Longitude')),
                  validator: (v) {
                    final n = double.tryParse(v ?? '');
                    return n == null || !n.isFinite || n < -180 || n > 180
                        ? _t('Неверная долгота', 'Қате бойлық', 'Invalid longitude')
                        : null;
                  },
                )),
              ]),
              const SizedBox(height: 12),
              FilledButton(
                  onPressed: _busy ? null : _create,
                  child: Text(_t('Добавить адрес', 'Мекенжай қосу',
                      'Add address'))),
            ]),
          ),
        ],
      );

  @override
  void dispose() {
    _label.dispose();
    _address.dispose();
    _latitude.dispose();
    _longitude.dispose();
    super.dispose();
  }
}
