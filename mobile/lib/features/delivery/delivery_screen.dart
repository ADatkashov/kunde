import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:kunde_design/kunde_design.dart';

import '../identity/auth_repository.dart';
import '../identity/support_panel.dart';
import '../rides/ride_api.dart';
import 'delivery_api.dart';
import 'delivery_strings.dart';

class DeliveryScreen extends StatefulWidget {
  const DeliveryScreen(
      {required this.api,
      required this.synthetic,
      this.intakeEnabled = true,
      this.draft,
      super.key});

  final DeliveryApi api;
  final bool synthetic;
  final bool intakeEnabled;
  final DeliveryOrder? draft;

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen> {
  static const types = [
    'DOCUMENTS',
    'SMALL_PARCEL',
    'MEDIUM_PARCEL',
    'PERSONAL_ITEMS',
    'OTHER_ALLOWED_GOODS',
  ];
  static const _fieldIds = [
    'delivery-weight',
    'delivery-length',
    'delivery-width',
    'delivery-height',
    'delivery-recipient',
    'delivery-phone',
    'delivery-description',
    'delivery-note',
  ];
  final _form = GlobalKey<FormState>();
  final _fields = List.generate(8, (_) => TextEditingController());
  RideAddress? _pickup;
  RideAddress? _destination;
  String _type = 'DOCUMENTS';
  bool _allowed = false;
  bool _busy = false;
  bool _confirmationStarted = false;
  bool _error = false;
  DeliveryQuote? _quote;
  String? _key;

  @override
  void initState() {
    super.initState();
    final draft = widget.draft;
    if (draft == null || !draft.repeatable) return;
    _pickup = RideAddress(draft.pickup, draft.pickupPoint!);
    _destination = RideAddress(draft.destination, draft.destinationPoint!);
    if (types.contains(draft.parcelType)) _type = draft.parcelType!;
    final parcel = draft.parcel!;
    final values = [
      parcel['weightGrams'],
      parcel['lengthCm'],
      parcel['widthCm'],
      parcel['heightCm'],
      draft.recipientName,
      draft.recipientPhone,
      draft.description,
      draft.courierNote
    ];
    for (var i = 0; i < _fields.length; i++) {
      _fields[i].text = values[i]?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    for (final field in _fields) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _pick(bool pickup) async {
    final addresses = widget.api.addresses();
    final selection = await showModalBottomSheet<RideAddress>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) {
        final s = DeliveryStrings(context);
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .55,
            child: FutureBuilder(
              future: addresses,
              builder: (context, snapshot) {
                final available = [
                  if (widget.synthetic)
                    if (pickup)
                      RideAddress(
                          s.t('[DEV/TEST] Отправитель', '[DEV/TEST] Жіберуші',
                              '[DEV/TEST] Pickup'),
                          const {'latitude': 43.24, 'longitude': 76.92})
                    else
                      RideAddress(
                          s.t('[DEV/TEST] Получатель', '[DEV/TEST] Алушы',
                              '[DEV/TEST] Destination'),
                          const {'latitude': 43.25, 'longitude': 76.94}),
                  ...?snapshot.data,
                ];
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(pickup ? s.pickup : s.destination,
                        style: Theme.of(context).textTheme.titleLarge),
                    for (final item in available)
                      ListTile(
                          title: Text(item.label),
                          onTap: () => Navigator.pop(context, item)),
                    if (snapshot.connectionState != ConnectionState.done)
                      const LinearProgressIndicator()
                    else if (snapshot.hasError)
                      Text(s.error)
                    else if (available.isEmpty)
                      Text(s.t(
                          'Добавьте адрес в профиле.',
                          'Мекенжайды профильге қосыңыз.',
                          'Add an address in Profile.')),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
    if (!mounted || selection == null) return;
    setState(() {
      if (pickup) {
        _pickup = selection;
      } else {
        _destination = selection;
      }
      _error = false;
    });
  }

  Future<void> _submit() async {
    if (_busy ||
        !(_form.currentState?.validate() ?? false) ||
        _pickup == null ||
        _destination == null ||
        !_allowed) {
      return;
    }
    setState(() {
      _busy = true;
      _error = false;
    });
    try {
      final quote = _quote;
      if (quote == null) {
        final next = await widget.api.quote(_pickup!, _destination!, _type,
            _fields.take(4).map((field) => int.parse(field.text)).toList());
        if (!mounted) return;
        final random = Random.secure();
        setState(() {
          _quote = next;
          _key = base64UrlEncode(List.generate(18, (_) => random.nextInt(256)));
        });
        return;
      }
      _confirmationStarted = true;
      final order = await widget.api.create({
        'quoteId': quote.id,
        'pickupAddress': _pickup!.label,
        'destinationAddress': _destination!.label,
        'recipientName': _fields[4].text.trim(),
        'recipientPhone': _fields[5].text.trim(),
        'description': _fields[6].text.trim(),
        'courierNote': _fields[7].text.trim(),
        'allowedGoodsConfirmed': _allowed,
      }, _key!);
      if (!mounted) return;
      setState(() {
        _quote = null;
        _key = null;
        _confirmationStarted = false;
        _allowed = false;
      });
      await Navigator.push<void>(
          context,
          MaterialPageRoute(
              builder: (_) => _Details(
                  api: widget.api,
                  initial: order,
                  syntheticRouting: widget.synthetic)));
    } on IdentityApiError catch (error) {
      if (!mounted) return;
      setState(() {
        if (error.code == 'DELIVERY_QUOTE_UNAVAILABLE') {
          _quote = null;
          _key = null;
          _confirmationStarted = false;
        }
        _error = true;
      });
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.intakeEnabled) {
      return _History(api: widget.api, allowDispatch: false);
    }
    final s = DeliveryStrings(context);
    final quote = _quote;
    final locked = _busy || quote != null;
    final minutes = quote == null ? 0 : (quote.duration / 60).ceil();
    final labels = [
      s.t('Вес, г', 'Салмақ, г', 'Weight, g'),
      s.t('Длина, см', 'Ұзындығы, см', 'Length, cm'),
      s.t('Ширина, см', 'Ені, см', 'Width, cm'),
      s.t('Высота, см', 'Биіктігі, см', 'Height, cm'),
      s.t('Имя получателя', 'Алушының аты', 'Recipient name'),
      s.t('Телефон получателя', 'Алушының телефоны', 'Recipient phone'),
      s.t('Описание', 'Сипаттамасы', 'Description'),
      s.t('Комментарий курьеру', 'Курьерге ескерту', 'Courier note'),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(s.title), actions: [
        IconButton(
          tooltip: s.history,
          icon: const Icon(Icons.history_rounded),
          onPressed: _busy
              ? null
              : () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                      builder: (_) => _History(
                          api: widget.api,
                          syntheticRouting: widget.synthetic))),
        ),
      ]),
      body: SafeArea(
          child: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: KundePalette.heroGradient,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.t(
                          'Отправить посылку',
                          'Сәлемдеме жіберу',
                          'Send a parcel',
                        ),
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Image.asset(
                      'assets/illustrations/delivery.png',
                      width: 64,
                      height: 64,
                      excludeFromSemantics: true,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
                child: Column(children: [
              ListTile(
                leading: const Icon(Icons.radio_button_checked),
                title: Text(s.pickup),
                subtitle: _pickup == null ? null : Text(_pickup!.label),
                onTap: locked ? null : () => _pick(true),
              ),
              ListTile(
                leading: const Icon(Icons.location_on_outlined),
                title: Text(s.destination),
                subtitle:
                    _destination == null ? null : Text(_destination!.label),
                onTap: locked ? null : () => _pick(false),
              ),
            ])),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _type,
              isExpanded: true,
              decoration: InputDecoration(
                  labelText:
                      s.t('Тип отправления', 'Жөнелтілім түрі', 'Parcel type')),
              items: [
                for (final type in types)
                  DropdownMenuItem(value: type, child: Text(s.parcel(type))),
              ],
              onChanged:
                  locked ? null : (value) => setState(() => _type = value!),
            ),
            for (var index = 0; index < _fields.length; index++)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Semantics(
                  identifier: _fieldIds[index],
                  child: TextFormField(
                    enabled: !locked,
                    controller: _fields[index],
                    decoration: InputDecoration(labelText: labels[index]),
                    keyboardType: index < 4
                        ? TextInputType.number
                        : index == 5
                            ? TextInputType.phone
                            : TextInputType.text,
                    maxLength: [5, 3, 3, 3, 120, 16, 300, 300][index],
                    validator: (value) =>
                        _validate(s, index, value?.trim() ?? ''),
                  ),
                ),
              ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _allowed,
              onChanged: locked
                  ? null
                  : (value) => setState(() => _allowed = value == true),
              title: Text(s.t(
                  'В отправлении нет запрещённых или опасных предметов',
                  'Жөнелтілімде тыйым салынған немесе қауіпті заттар жоқ',
                  'The shipment contains no prohibited or dangerous items')),
            ),
            if (quote != null)
              Card(
                  child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (quote.synthetic) Text(s.testRoute),
                      Text('${quote.amount} ₸',
                          style: Theme.of(context).textTheme.titleLarge),
                      Text(s.t(
                          '${quote.distance} м · $minutes мин',
                          '${quote.distance} м · $minutes мин',
                          '${quote.distance} m · $minutes min')),
                      Text(s.t(
                          'Тестовая доставка без оплаты.',
                          'Сынақ жеткізілімі төлемсіз.',
                          'Test shipment without payment.')),
                      Text(s.t(
                          'Отмена доступна до забора.',
                          'Алып кеткенге дейін бас тартуға болады.',
                          'Cancellation is available before pickup.')),
                    ]),
              )),
            if (_error) Semantics(liveRegion: true, child: Text(s.error)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed:
                  _busy || _pickup == null || _destination == null || !_allowed
                      ? null
                      : _submit,
              child: Text(quote == null
                  ? s.t(
                      'Рассчитать стоимость', 'Бағасын есептеу', 'Get a quote')
                  : s.t('Подтвердить доставку', 'Жеткізуді растау',
                      'Confirm delivery')),
            ),
            if (quote != null && !_confirmationStarted)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _quote = null;
                          _key = null;
                        }),
                child: Text(s.t('Изменить отправление', 'Жөнелтілімді өзгерту',
                    'Edit shipment')),
              ),
            if (_busy) const LinearProgressIndicator(),
          ],
        ),
      )),
    );
  }

  String? _validate(DeliveryStrings s, int index, String value) {
    if (index != 7 && value.isEmpty) return s.required;
    if (index < 4) {
      final number = int.tryParse(value);
      final weightLimit = _type == 'DOCUMENTS' ? 2000 : 30000;
      final limit = index == 0 ? weightLimit : 200;
      if (number == null || number < 1 || number > limit) {
        return index == 0
            ? s.t(
                'Укажите вес от 1 до $weightLimit г',
                'Салмақты 1–$weightLimit г аралығында көрсетіңіз',
                'Enter a weight between 1 and $weightLimit g')
            : s.t('Проверьте число', 'Санды тексеріңіз', 'Check the number');
      }
    }
    if (index == 5 && !RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(value)) {
      return s.t('Используйте формат +7…', '+7… пішімін қолданыңыз',
          'Use the +7… format');
    }
    return null;
  }
}

class _History extends StatefulWidget {
  const _History(
      {required this.api,
      this.allowDispatch = true,
      this.syntheticRouting = false});
  final DeliveryApi api;
  final bool allowDispatch;
  final bool syntheticRouting;

  @override
  State<_History> createState() => _HistoryState();
}

class _HistoryState extends State<_History> {
  late Future<List<DeliveryOrder>> _history = widget.api.history();

  void _reloadHistory() {
    setState(() {
      _history = widget.api.history();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = DeliveryStrings(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.history)),
      body: SafeArea(
          child: FutureBuilder(
        future: _history,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
                child: TextButton(
              onPressed: _reloadHistory,
              child: Text(s.retry),
            ));
          }
          final orders = snapshot.data!;
          if (orders.isEmpty) {
            return Center(
                child: Text(s.t('Отправлений пока нет.',
                    'Әзірге жөнелтілім жоқ.', 'No shipments yet.')));
          }
          return ListView(children: [
            for (final order in orders)
              ListTile(
                title: Text('${order.pickup} → ${order.destination}'),
                subtitle: Text(s.status(order.status)),
                onTap: () async {
                  await Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                          builder: (_) => _Details(
                              api: widget.api,
                              initial: order,
                              allowDispatch: widget.allowDispatch,
                              syntheticRouting: widget.syntheticRouting)));
                  if (mounted) _reloadHistory();
                },
              ),
          ]);
        },
      )),
    );
  }
}

class _Details extends StatefulWidget {
  const _Details(
      {required this.api,
      required this.initial,
      this.allowDispatch = true,
      this.syntheticRouting = false});
  final DeliveryApi api;
  final DeliveryOrder initial;
  final bool allowDispatch;
  final bool syntheticRouting;

  @override
  State<_Details> createState() => _DetailsState();
}

class _DetailsState extends State<_Details> {
  late DeliveryOrder _order = widget.initial;
  Timer? _poll;
  bool _busy = false;
  bool _failed = false;
  (String, DateTime)? _code;
  (double, double)? _location;
  static const _trackable = {
    'COURIER_ASSIGNED',
    'COURIER_ARRIVING',
    'COURIER_ARRIVED',
    'PICKED_UP',
    'IN_TRANSIT',
    'RETURNING'
  };

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      if (ModalRoute.of(context)?.isCurrent == true &&
          !const {
            'COMPLETED',
            'NO_COURIER_AVAILABLE',
            'RETURNED_TO_SENDER',
            'PICKUP_FAILED',
            'CANCELLED_BY_CUSTOMER',
            'CANCELLED_BY_COURIER',
            'CANCELLED_BY_SYSTEM',
            'DISPUTED'
          }.contains(_order.status)) {
        unawaited(_refresh());
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh());
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _change(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted && _failed) setState(() => _failed = false);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() => _change(() async {
        final latest = await widget.api.detail(_order.id);
        if (!mounted) return;
        setState(() => _order = latest);
        if (latest.searching && widget.allowDispatch) {
          final dispatched = await widget.api.dispatch(latest.id);
          if (mounted) setState(() => _order = dispatched);
        }
        if (!mounted) return;
        if (_order.status != 'IN_TRANSIT') setState(() => _code = null);
        if (_trackable.contains(_order.status)) {
          try {
            final point = await widget.api.location(_order.id);
            if (mounted) setState(() => _location = point);
          } catch (_) {
            if (mounted) setState(() => _location = null);
          }
        } else {
          setState(() => _location = null);
        }
      });

  Future<void> _cancel(DeliveryStrings s) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(title: Text(s.cancel), actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.close)),
        FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.cancel)),
      ]),
    );
    if (!mounted || confirm != true) return;
    await _change(() async {
      final updated = await widget.api.cancel(_order.id);
      if (mounted) setState(() => _order = updated);
    });
  }

  Future<void> _rate(DeliveryStrings s) async {
    final rating = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(s.t('Оценить курьера', 'Курьерді бағалау', 'Rate courier')),
        children: [
          for (final stars in [5, 4, 3, 2, 1])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, stars),
              child: Text('$stars / 5'),
            ),
        ],
      ),
    );
    if (!mounted || rating == null) return;
    await _change(() async {
      final rated = await widget.api.rate(_order.id, rating);
      if (mounted) setState(() => _order = rated);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = DeliveryStrings(context);
    final code = _code?.$2.isAfter(DateTime.now()) == true ? _code : null;
    final distance = _order.distanceMeters;
    final duration = _order.durationSeconds;
    final minutes = duration == null ? null : (duration / 60).ceil();
    return Scaffold(
      appBar: AppBar(title: Text(s.title)),
      body: SafeArea(
          child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Semantics(
              liveRegion: true,
              child: Text(s.status(_order.status),
                  style: Theme.of(context).textTheme.headlineSmall)),
          if (_order.synthetic) Text(s.testRoute),
          ListTile(
              leading: const Icon(Icons.radio_button_checked),
              title: Text(_order.pickup)),
          ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: Text(_order.destination)),
          if (_order.courier case final courier?)
            ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(courier)),
          if (_location case final point?)
            ListTile(
              leading: const Icon(Icons.my_location),
              title: Text(
                  s.t('Точка курьера', 'Курьердің орны', 'Courier location')),
              subtitle: Text(
                  '${point.$1.toStringAsFixed(5)}, ${point.$2.toStringAsFixed(5)}'),
            ),
          Text('${_order.amount} ₸'),
          if (distance != null && minutes != null)
            Text(s.t(
                'Маршрут: $distance м · около $minutes мин',
                'Бағыт: $distance м · шамамен $minutes мин',
                'Route: $distance m · about $minutes min')),
          if (_order.parcel case final parcel?)
            ListTile(
              title: Text(s.parcel(_order.parcelType ?? 'OTHER_ALLOWED_GOODS')),
              subtitle: Text(s.t('${parcel['weightGrams']} г',
                  '${parcel['weightGrams']} г', '${parcel['weightGrams']} g')),
            ),
          if (_order.status == 'COMPLETED') ...[
            if (_order.stars case final rating?)
              ListTile(
                  leading: const Icon(Icons.star_outline),
                  title: Text(
                      s.t('Оценка курьера', 'Курьер бағасы', 'Courier rating')),
                  subtitle: Text('$rating / 5')),
            if (_order.stars == null)
              OutlinedButton(
                  onPressed: _busy ? null : () => _rate(s),
                  child: Text(s.t(
                      'Оценить курьера', 'Курьерді бағалау', 'Rate courier'))),
          ],
          if (widget.allowDispatch &&
              !_order.active &&
              _order.repeatable &&
              (!_order.synthetic || widget.syntheticRouting))
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                          builder: (_) => DeliveryScreen(
                              api: widget.api,
                              synthetic: widget.syntheticRouting,
                              draft: _order))),
              child: Text(s.t('Повторить отправление', 'Жөнелтілімді қайталау',
                  'Repeat shipment')),
            ),
          if (_order.status == 'IN_TRANSIT')
            if (code != null) ...[
              Text(s.t(
                  'DEV/TEST · передайте код получателю',
                  'DEV/TEST · кодты алушыға беріңіз',
                  'DEV/TEST · share the code with the recipient')),
              SelectableText(code.$1),
              Text(MaterialLocalizations.of(context)
                  .formatTimeOfDay(TimeOfDay.fromDateTime(code.$2.toLocal()))),
            ] else
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _change(() async {
                          final issued =
                              await widget.api.handoffCode(_order.id);
                          if (mounted) setState(() => _code = issued);
                        }),
                child: Text(s.t('Получить код вручения', 'Тапсыру кодын алу',
                    'Get handoff code')),
              ),
          if (_failed) Semantics(liveRegion: true, child: Text(s.error)),
          TextButton(
              onPressed: _busy ? null : _refresh,
              child: Text(
                  s.t('Обновить статус', 'Күйді жаңарту', 'Refresh status'))),
          if (_order.cancellable)
            OutlinedButton(
                onPressed: _busy ? null : () => _cancel(s),
                child: Text(s.cancel)),
          TextButton.icon(
            icon: const Icon(Icons.support_agent),
            label: Text(s.t('Обратиться в поддержку', 'Қолдау қызметіне жазу',
                'Contact support')),
            onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(
                        title: Text(s.t('Поддержка', 'Қолдау', 'Support'))),
                    body: SafeArea(
                        child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        SupportPanel(
                            auth: widget.api.auth, deliveryId: _order.id)
                      ],
                    )),
                  ),
                )),
          ),
          if (_busy) const LinearProgressIndicator(),
        ],
      )),
    );
  }
}
