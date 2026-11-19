import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../data/partner_api.dart';
import '../../data/partner_operations.dart';

class BusinessDeliveryScreen extends StatefulWidget {
  const BusinessDeliveryScreen({
    required this.ops,
    required this.synthetic,
    super.key,
  });

  final PartnerOperations ops;
  final bool synthetic;

  @override
  State<BusinessDeliveryScreen> createState() => _BusinessDeliveryScreenState();
}

class _BusinessDeliveryScreenState extends State<BusinessDeliveryScreen> {
  late Future<_ShipmentData> _data = _fetch();

  Future<_ShipmentData> _fetch() async => (
        orders: await widget.ops.shipments(),
        totals: await widget.ops.shipmentTotals(),
      );

  void _refresh() {
    setState(() {
      _data = _fetch();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = _Copy(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.title)),
      body: SafeArea(
        child: FutureBuilder(
          future: _data,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: OutlinedButton(
                  onPressed: _refresh,
                  child: Text(s.error),
                ),
              );
            }
            final data = snapshot.data!;
            return RefreshIndicator(
              onRefresh: () async {
                _refresh();
                await _data;
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  if (widget.synthetic)
                    FilledButton.icon(
                      icon: const Icon(Icons.add),
                      label: Text(
                        s.t(
                          'Новое тестовое отправление',
                          'Жаңа сынақ жөнелтілімі',
                          'New test shipment',
                        ),
                      ),
                      onPressed: () async {
                        await Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => _ShipmentForm(ops: widget.ops),
                          ),
                        );
                        if (mounted) _refresh();
                      },
                    ),
                  if (data.totals.isNotEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.t(
                                'Отправления и суммы котировок',
                                'Жөнелтілімдер мен бағалар жиыны',
                                'Shipments and quoted totals',
                              ),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            for (final row in data.totals)
                              Text(
                                '${s.status(row['status'])} · ${row['shipmentCount']} · ${row['quotedTotalKzt']} ₸',
                              ),
                          ],
                        ),
                      ),
                    ),
                  if (data.orders.isEmpty)
                    Text(
                      s.t(
                        'Отправлений пока нет.',
                        'Әзірге жөнелтілім жоқ.',
                        'No shipments yet.',
                      ),
                    ),
                  for (final order in data.orders)
                    ListTile(
                      title: Text(
                        '${order['pickupAddress']} → ${order['destinationAddress']}',
                      ),
                      subtitle: Text(
                        '${s.status(order['status'])} · ${order['amountKzt']} ₸',
                      ),
                      onTap: () async {
                        await Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => _ShipmentDetails(
                              ops: widget.ops,
                              initial: order,
                            ),
                          ),
                        );
                        if (mounted) _refresh();
                      },
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

typedef _ShipmentData = ({
  List<Map<String, dynamic>> orders,
  List<Map<String, dynamic>> totals,
});

class _ShipmentForm extends StatefulWidget {
  const _ShipmentForm({required this.ops});

  final PartnerOperations ops;

  @override
  State<_ShipmentForm> createState() => _ShipmentFormState();
}

class _ShipmentFormState extends State<_ShipmentForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _description = TextEditingController();
  final _measurement = List.generate(4, (_) => TextEditingController());
  String _type = 'DOCUMENTS';
  bool _allowed = false;
  bool _busy = false;
  bool _error = false;
  Map<String, dynamic>? _quote;
  String? _key;

  @override
  void dispose() {
    for (final controller in [_name, _phone, _description, ..._measurement]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_allowed || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = false;
    });
    try {
      const pickup = {'latitude': 43.24, 'longitude': 76.92};
      const destination = {'latitude': 43.25, 'longitude': 76.94};
      final quote = _quote;
      if (quote == null) {
        final measures =
            _measurement.map((field) => int.parse(field.text.trim())).toList();
        final result = await widget.ops.shipmentQuote({
          'pickup': pickup,
          'destination': destination,
          'parcelType': _type,
          'weightGrams': measures[0],
          'lengthCm': measures[1],
          'widthCm': measures[2],
          'heightCm': measures[3],
        });
        if (!mounted) return;
        final random = Random.secure();
        setState(() {
          _quote = result;
          _key = base64UrlEncode(List.generate(18, (_) => random.nextInt(256)));
        });
      } else {
        final s = _Copy(context);
        final order = await widget.ops.createShipment({
          'quoteId': quote['id'],
          'pickupAddress': s.pickup,
          'destinationAddress': s.destination,
          'recipientName': _name.text.trim(),
          'recipientPhone': _phone.text.trim(),
          'description': _description.text.trim(),
          'allowedGoodsConfirmed': _allowed,
        }, _key!);
        if (!mounted) return;
        await Navigator.pushReplacement<void, void>(
          context,
          MaterialPageRoute(
            builder: (_) => _ShipmentDetails(ops: widget.ops, initial: order),
          ),
        );
      }
    } on PartnerApiException catch (error) {
      if (mounted) {
        setState(() {
          if (error.code == 'DELIVERY_QUOTE_UNAVAILABLE') {
            _quote = null;
            _key = null;
          }
          _error = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _Copy(context);
    final quote = _quote;
    final enabled = !_busy && quote == null;
    final measures = [
      s.t('Вес, г', 'Салмақ, г', 'Weight, g'),
      s.t('Длина, см', 'Ұзындығы, см', 'Length, cm'),
      s.t('Ширина, см', 'Ені, см', 'Width, cm'),
      s.t('Высота, см', 'Биіктігі, см', 'Height, cm'),
    ];
    final types = {
      'DOCUMENTS': s.t('Документы', 'Құжаттар', 'Documents'),
      'SMALL_PARCEL': s.t('Малая посылка', 'Шағын сәлемдеме', 'Small parcel'),
      'MEDIUM_PARCEL': s.t(
        'Средняя посылка',
        'Орташа сәлемдеме',
        'Medium parcel',
      ),
      'PERSONAL_ITEMS': s.t('Личные вещи', 'Жеке заттар', 'Personal items'),
      'OTHER_ALLOWED_GOODS': s.t(
        'Разрешённые вещи',
        'Рұқсат етілген заттар',
        'Allowed goods',
      ),
    };
    return Scaffold(
      appBar: AppBar(title: Text(s.title)),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ListTile(
                leading: const Icon(Icons.radio_button_checked),
                title: Text(s.pickup),
              ),
              ListTile(
                leading: const Icon(Icons.location_on_outlined),
                title: Text(s.destination),
              ),
              DropdownButtonFormField<String>(
                initialValue: _type,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: s.t('Отправление', 'Жөнелтілім', 'Parcel'),
                ),
                items: [
                  for (final item in types.entries)
                    DropdownMenuItem(value: item.key, child: Text(item.value)),
                ],
                onChanged:
                    enabled ? (value) => setState(() => _type = value!) : null,
              ),
              for (var index = 0; index < measures.length; index++)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: TextFormField(
                    controller: _measurement[index],
                    enabled: enabled,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: measures[index]),
                    validator: (value) {
                      final number = int.tryParse(value?.trim() ?? '');
                      return number == null ||
                              number < 1 ||
                              number > (index == 0 ? 50000 : 200)
                          ? s.required
                          : null;
                    },
                  ),
                ),
              for (final field in [
                (
                  _name,
                  s.t('Имя получателя', 'Алушының аты', 'Recipient name'),
                  120,
                ),
                (
                  _phone,
                  s.t(
                    'Телефон получателя',
                    'Алушының телефоны',
                    'Recipient phone',
                  ),
                  16,
                ),
                (
                  _description,
                  s.t('Описание', 'Сипаттамасы', 'Description'),
                  300,
                ),
              ])
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: TextFormField(
                    controller: field.$1,
                    enabled: enabled,
                    decoration: InputDecoration(labelText: field.$2),
                    maxLength: field.$3,
                    keyboardType: field.$1 == _phone
                        ? TextInputType.phone
                        : TextInputType.text,
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (text.isEmpty) return s.required;
                      if (field.$1 == _phone &&
                          !RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(text)) {
                        return s.t(
                          'Используйте формат +7…',
                          '+7… пішімін қолданыңыз',
                          'Use the +7… format',
                        );
                      }
                      return null;
                    },
                  ),
                ),
              CheckboxListTile(
                value: _allowed,
                onChanged: enabled
                    ? (value) => setState(() => _allowed = value == true)
                    : null,
                title: Text(
                  s.t(
                    'В отправлении нет запрещённых или опасных предметов',
                    'Жөнелтілімде тыйым салынған немесе қауіпті заттар жоқ',
                    'The shipment contains no prohibited or dangerous items',
                  ),
                ),
              ),
              if (quote != null)
                ListTile(
                  title: Text('${quote['amountKzt']} ₸'),
                  subtitle: Text(
                    s.t(
                      'DEV/TEST · тестовый маршрут без оплаты',
                      'DEV/TEST · төлемсіз сынақ бағыты',
                      'DEV/TEST · synthetic route without payment',
                    ),
                  ),
                ),
              if (_error) Semantics(liveRegion: true, child: Text(s.error)),
              FilledButton(
                onPressed: _busy || !_allowed ? null : _submit,
                child: Text(
                  quote == null
                      ? s.t(
                          'Рассчитать стоимость',
                          'Бағасын есептеу',
                          'Get a quote',
                        )
                      : s.t(
                          'Подтвердить отправление',
                          'Жөнелтілімді растау',
                          'Confirm shipment',
                        ),
                ),
              ),
              if (_busy) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShipmentDetails extends StatefulWidget {
  const _ShipmentDetails({required this.ops, required this.initial});

  final PartnerOperations ops;
  final Map<String, dynamic> initial;

  @override
  State<_ShipmentDetails> createState() => _ShipmentDetailsState();
}

class _ShipmentDetailsState extends State<_ShipmentDetails> {
  late Map<String, dynamic> _order = widget.initial;
  String? _code;
  bool _busy = false;
  bool _error = false;

  Future<void> _action(String action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await widget.ops.shipmentAction(
        _order['id'] as String,
        action,
      );
      if (!mounted) return;
      setState(() {
        _error = false;
        if (action == 'handoff-code') {
          _code = result['code'] as String;
        } else {
          _order = result;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final updated = await widget.ops.shipment(_order['id'] as String);
      if (mounted) {
        setState(() {
          _order = updated;
          _error = false;
          if (updated['status'] != 'IN_TRANSIT') _code = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _Copy(context);
    final state = _order['status'];
    final searching = state == 'CREATED' || state == 'SEARCHING_COURIER';
    final cancellable = searching ||
        const {
          'COURIER_ASSIGNED',
          'COURIER_ARRIVING',
          'COURIER_ARRIVED',
        }.contains(state);
    return Scaffold(
      appBar: AppBar(title: Text(s.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              s.status(state),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(_order['pickupAddress'] as String),
            Text(_order['destinationAddress'] as String),
            Text('${_order['amountKzt']} ₸'),
            if (searching)
              FilledButton(
                onPressed: _busy ? null : () => _action('dispatch'),
                child: Text(
                  s.t('Подобрать курьера', 'Курьерді іздеу', 'Find a courier'),
                ),
              ),
            if (cancellable)
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () async {
                        final label = s.t(
                          'Отменить отправление',
                          'Жөнелтілімнен бас тарту',
                          'Cancel shipment',
                        );
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text(label),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: Text(s.t('Закрыть', 'Жабу', 'Close')),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: Text(label),
                              ),
                            ],
                          ),
                        );
                        if (mounted && confirmed == true) {
                          await _action('cancel');
                        }
                      },
                child: Text(
                  s.t(
                    'Отменить отправление',
                    'Жөнелтілімнен бас тарту',
                    'Cancel shipment',
                  ),
                ),
              ),
            if (state == 'IN_TRANSIT')
              if (_code case final code?)
                SelectableText(code)
              else
                OutlinedButton(
                  onPressed: _busy ? null : () => _action('handoff-code'),
                  child: Text(
                    s.t(
                      'DEV/TEST · код вручения',
                      'DEV/TEST · тапсыру коды',
                      'DEV/TEST · handoff code',
                    ),
                  ),
                ),
            if (_error) Semantics(liveRegion: true, child: Text(s.error)),
            TextButton(
              onPressed: _busy ? null : _refresh,
              child: Text(s.t('Обновить', 'Жаңарту', 'Refresh')),
            ),
            if (_busy) const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

class _Copy {
  _Copy(BuildContext context)
      : language = Localizations.localeOf(context).languageCode;

  final String language;

  String t(String ru, String kk, String en) => switch (language) {
        'ru' => ru,
        'kk' => kk,
        _ => en,
      };

  String get title => t(
        'Доставка для бизнеса',
        'Бизнеске арналған жеткізу',
        'Business delivery',
      );
  String get pickup =>
      t('[DEV/TEST] Склад', '[DEV/TEST] Қойма', '[DEV/TEST] Warehouse');
  String get destination =>
      t('[DEV/TEST] Получатель', '[DEV/TEST] Алушы', '[DEV/TEST] Recipient');
  String get error => t(
        'Не удалось выполнить запрос. Повторите попытку.',
        'Сұрау орындалмады. Қайталап көріңіз.',
        'Could not complete the request. Try again.',
      );
  String get required =>
      t('Проверьте поле', 'Өрісті тексеріңіз', 'Check this field');

  String status(Object? status) => switch (status) {
        'CREATED' => t('Создано', 'Жасалды', 'Created'),
        'SEARCHING_COURIER' => t(
            'Поиск курьера',
            'Курьерді іздеу',
            'Finding a courier',
          ),
        'COURIER_ASSIGNED' => t(
            'Курьер назначен',
            'Курьер тағайындалды',
            'Courier assigned',
          ),
        'COURIER_ARRIVING' => t(
            'Курьер в пути',
            'Курьер жолда',
            'Courier on the way',
          ),
        'COURIER_ARRIVED' =>
          t('Курьер прибыл', 'Курьер келді', 'Courier arrived'),
        'PICKED_UP' =>
          t('Посылка у курьера', 'Сәлемдеме курьерде', 'Picked up'),
        'IN_TRANSIT' => t('В пути', 'Жолда', 'In transit'),
        'DELIVERED' => t('Вручено', 'Тапсырылды', 'Delivered'),
        'COMPLETED' => t('Завершено', 'Аяқталды', 'Completed'),
        'CANCELLED_BY_CUSTOMER' ||
        'CANCELLED_BY_COURIER' ||
        'CANCELLED_BY_SYSTEM' =>
          t('Отменено', 'Бас тартылды', 'Cancelled'),
        'NO_COURIER_AVAILABLE' => t(
            'Курьер не найден',
            'Курьер табылмады',
            'No courier available',
          ),
        'PICKUP_FAILED' ||
        'DELIVERY_FAILED' =>
          t('Не выполнено', 'Орындалмады', 'Failed'),
        'RETURN_REQUESTED' ||
        'RETURNING' =>
          t('Возврат', 'Қайтару', 'Returning'),
        'RETURNED_TO_SENDER' => t('Возвращено', 'Қайтарылды', 'Returned'),
        'DISPUTED' => t('На рассмотрении', 'Қаралуда', 'Under review'),
        _ => t('Статус недоступен', 'Күйі қолжетімсіз', 'Status unavailable'),
      };
}
