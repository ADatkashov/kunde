import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../delivery/delivery_strings.dart';
import '../identity/auth_repository.dart';

class DeliveryWorkScreen extends StatefulWidget {
  const DeliveryWorkScreen(
      {required this.auth, required this.synthetic, super.key});

  final AuthRepository auth;
  final bool synthetic;

  @override
  State<DeliveryWorkScreen> createState() => _DeliveryWorkScreenState();
}

class _DeliveryWorkScreenState extends State<DeliveryWorkScreen> {
  static const _root = 'executor/deliveries';
  final _name = TextEditingController();
  String _vehicle = 'BICYCLE';
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _offers = [];
  List<Map<String, dynamic>> _shipments = [];
  bool _busy = false;
  bool _loaded = false;
  bool _error = false;
  bool _handoffError = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _poll = Timer.periodic(const Duration(seconds: 7), (_) {
      if (ModalRoute.of(context)?.isCurrent == true && _profile != null) {
        unawaited(_load());
      }
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _name.dispose();
    super.dispose();
  }

  Future<dynamic> _call(String method, String path,
          {Map<String, dynamic>? body, Set<int> expected = const {200}}) =>
      widget.auth.authorizedJson(method, path, body: body, expected: expected);

  Future<void> _load([Future<dynamic> Function()? action]) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      if (action != null) _handoffError = false;
    });
    try {
      if (action != null) await action();
      Map<String, dynamic>? profile;
      try {
        profile = await _call('GET', '$_root/profile') as Map<String, dynamic>;
      } on IdentityApiError catch (failure) {
        if (failure.code != 'DELIVERY_COURIER_NOT_FOUND') rethrow;
      }
      final offers = profile?['online'] == true
          ? (await _call('GET', '$_root/offers') as List)
              .cast<Map<String, dynamic>>()
          : <Map<String, dynamic>>[];
      final shipments = profile == null
          ? <Map<String, dynamic>>[]
          : (await _call('GET', _root) as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _offers = offers;
        _shipments = shipments;
        _loaded = true;
        _error = false;
      });
    } on IdentityApiError catch (failure) {
      if (mounted) {
        setState(() {
          _handoffError = failure.status == 422;
          _error = !_handoffError;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendLocation({required bool fixture}) => _load(() async {
        final double latitude;
        final double longitude;
        if (fixture) {
          latitude = 43.24;
          longitude = 76.92;
        } else {
          if (!await Geolocator.isLocationServiceEnabled()) {
            throw IdentityUnavailable();
          }
          var permission = await Geolocator.checkPermission();
          if (permission == LocationPermission.denied) {
            permission = await Geolocator.requestPermission();
          }
          if (permission != LocationPermission.whileInUse &&
              permission != LocationPermission.always) {
            throw IdentityUnavailable();
          }
          final position = await Geolocator.getCurrentPosition(
            locationSettings:
                const LocationSettings(timeLimit: Duration(seconds: 12)),
          );
          latitude = position.latitude;
          longitude = position.longitude;
        }
        if (!mounted) return;
        await _call('PUT', '$_root/location',
            body: {'latitude': latitude, 'longitude': longitude},
            expected: {204});
      });

  Future<void> _handoff(String id, DeliveryStrings s) async {
    var code = '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, update) {
        return AlertDialog(
          title: Text(s.t('Код вручения', 'Тапсыру коды', 'Handoff code')),
          content: TextField(
            keyboardType: TextInputType.number,
            maxLength: 8,
            obscureText: true,
            decoration:
                InputDecoration(labelText: s.t('8 цифр', '8 сан', '8 digits')),
            onChanged: (value) => update(() => code = value),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(s.close)),
            FilledButton(
              onPressed: RegExp(r'^[0-9]{8}$').hasMatch(code)
                  ? () => Navigator.pop(context, true)
                  : null,
              child: Text(s.t('Проверить код', 'Кодты тексеру', 'Verify code')),
            ),
          ],
        );
      }),
    );
    if (mounted && confirmed == true) {
      await _load(() => _call('POST', '$_root/$id/handoff',
          body: {'code': code}, expected: {204}));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = DeliveryStrings(context);
    final profile = _profile;
    final approval = profile?['status'];
    final online = profile?['online'] == true;
    return Scaffold(
      appBar: AppBar(
          title: Text(s.t('KUNDE Курьер', 'KUNDE Курьер', 'KUNDE Courier'))),
      body: SafeArea(
          child: RefreshIndicator(
        onRefresh: () => _load(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_error) Semantics(liveRegion: true, child: Text(s.error)),
            if (_handoffError)
              Semantics(
                  liveRegion: true,
                  child: Text(s.t(
                      'Код неверен, просрочен или исчерпал попытки.',
                      'Код қате, мерзімі өткен немесе әрекеттер таусылған.',
                      'The code is incorrect, expired, or out of attempts.'))),
            if (_loaded && profile == null) ...[
              TextField(
                controller: _name,
                maxLength: 80,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                    labelText:
                        s.t('Имя курьера', 'Курьердің аты', 'Courier name')),
              ),
              DropdownButtonFormField<String>(
                initialValue: _vehicle,
                decoration: InputDecoration(
                    labelText: s.t('Транспорт', 'Көлік', 'Vehicle')),
                items: [
                  DropdownMenuItem(
                      value: 'WALK',
                      child: Text(s.t('Пешком', 'Жаяу', 'On foot'))),
                  DropdownMenuItem(
                      value: 'BICYCLE',
                      child: Text(s.t('Велосипед', 'Велосипед', 'Bicycle'))),
                  DropdownMenuItem(
                      value: 'MOTORCYCLE',
                      child: Text(s.t('Мотоцикл', 'Мотоцикл', 'Motorcycle'))),
                  DropdownMenuItem(
                      value: 'CAR',
                      child: Text(s.t('Автомобиль', 'Автокөлік', 'Car'))),
                ],
                onChanged:
                    _busy ? null : (value) => setState(() => _vehicle = value!),
              ),
              FilledButton(
                onPressed: _busy || _name.text.trim().isEmpty
                    ? null
                    : () => _load(() => _call('POST', '$_root/profile', body: {
                          'name': _name.text.trim(),
                          'vehicle': _vehicle
                        })),
                child: Text(s.t('Отправить на проверку', 'Тексеруге жіберу',
                    'Submit for review')),
              ),
            ],
            if (profile != null)
              ListTile(
                title: Text(profile['name'] as String),
                subtitle: Text(switch (approval) {
                  'APPROVED' => s.t(
                      'Допущен к доставке', 'Жеткізуге рұқсат бар', 'Approved'),
                  'BLOCKED' => s.t('Допуск приостановлен', 'Рұқсат тоқтатылды',
                      'Access suspended'),
                  _ => s.t(
                      'Ожидает проверки', 'Тексеру күтілуде', 'Pending review'),
                }),
              ),
            if (approval == 'APPROVED')
              SwitchListTile(
                title: Text(s.t('Готов принимать заказы',
                    'Тапсырыс қабылдауға дайынмын', 'Available for offers')),
                value: online,
                onChanged: _busy
                    ? null
                    : (value) => _load(() => _call('PUT', '$_root/availability',
                        body: {'online': value})),
              ),
            if (online) ...[
              OutlinedButton(
                onPressed: _busy ? null : () => _sendLocation(fixture: false),
                child: Text(s.t('Передать текущую точку',
                    'Ағымдағы орынды жіберу', 'Share current location')),
              ),
              if (widget.synthetic)
                OutlinedButton(
                  onPressed: _busy ? null : () => _sendLocation(fixture: true),
                  child: Text(s.t(
                      'DEV/TEST · передать тестовую точку',
                      'DEV/TEST · сынақ орнын жіберу',
                      'DEV/TEST · share synthetic location')),
                ),
              if (_offers.isEmpty)
                Text(s.t('Предложений пока нет.', 'Әзірге ұсыныс жоқ.',
                    'No offers yet.')),
            ],
            for (final offer in _offers) _offer(offer, s),
            if (_shipments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(s.history,
                    style: Theme.of(context).textTheme.titleLarge),
              ),
            for (final shipment in _shipments) _shipment(shipment, s),
            TextButton(
                onPressed: _busy ? null : () => _load(), child: Text(s.retry)),
          ],
        ),
      )),
    );
  }

  Widget _offer(Map<String, dynamic> offer, DeliveryStrings s) {
    final id = offer['id'] as String;
    final expires = DateTime.parse(offer['expiresAt'] as String).toLocal();
    final deadline = MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(expires));
    return Card(
        child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s.parcel(offer['parcelType'] as String)),
        if (offer['syntheticRoute'] == true) Text(s.testRoute),
        Text(s.t(
            '${offer['weightGrams']} г · ${offer['distanceMeters']} м',
            '${offer['weightGrams']} г · ${offer['distanceMeters']} м',
            '${offer['weightGrams']} g · ${offer['distanceMeters']} m')),
        Text(s.t('Принять до $deadline', '$deadline дейін қабылдау',
            'Accept by $deadline')),
        Wrap(spacing: 8, children: [
          for (final accept in [true, false])
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _load(() => _call(
                      'POST', '$_root/offers/$id/response',
                      body: {'accept': accept}, expected: {204})),
              child: Text(accept
                  ? s.t('Принять', 'Қабылдау', 'Accept')
                  : s.t('Отклонить', 'Қабылдамау', 'Reject')),
            ),
        ]),
      ]),
    ));
  }

  Widget _shipment(Map<String, dynamic> shipment, DeliveryStrings s) {
    final id = shipment['id'] as String;
    final status = shipment['status'] as String;
    final step = switch (status) {
      'COURIER_ASSIGNED' => ('DEPART', s.t('Выехать', 'Жолға шығу', 'Depart')),
      'COURIER_ARRIVING' => (
          'ARRIVE',
          s.t('Я на месте', 'Мен келдім', 'Arrived')
        ),
      'COURIER_ARRIVED' => (
          'PICK_UP',
          s.t('Забрал посылку', 'Сәлемдемені алдым', 'Picked up')
        ),
      'PICKED_UP' => (
          'TRANSIT',
          s.t('Еду к получателю', 'Алушыға барамын', 'Start transit')
        ),
      'DELIVERED' => (
          'COMPLETE',
          s.t('Завершить', 'Аяқтау', 'Complete delivery')
        ),
      'RETURN_REQUESTED' => (
          'START_RETURN',
          s.t('Начать возврат', 'Қайтаруды бастау', 'Start return')
        ),
      'RETURNING' => (
          'CONFIRM_RETURN',
          s.t('Посылка возвращена', 'Сәлемдеме қайтарылды', 'Confirm return')
        ),
      _ => null,
    };
    return Card(
        child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s.status(status)),
        Text(s.parcel(shipment['parcelType'] as String)),
        if (shipment['syntheticRoute'] == true) Text(s.testRoute),
        for (final key in [
          'pickupAddress',
          'destinationAddress',
          'courierNote'
        ])
          if (shipment[key] case final String content when content.isNotEmpty)
            Text(content),
        if (step != null)
          FilledButton(
              onPressed: _busy ? null : () => _progress(id, step.$1),
              child: Text(step.$2)),
        if (status == 'IN_TRANSIT')
          FilledButton(
              onPressed: _busy ? null : () => _handoff(id, s),
              child: Text(s.t('Подтвердить вручение', 'Тапсыруды растау',
                  'Confirm handoff'))),
        if (status == 'IN_TRANSIT' || status == 'COURIER_ARRIVED')
          TextButton(
              onPressed: _busy
                  ? null
                  : () => _progress(id,
                      status == 'IN_TRANSIT' ? 'FAIL_DELIVERY' : 'FAIL_PICKUP'),
              child: Text(status == 'IN_TRANSIT'
                  ? s.t('Получатель недоступен', 'Алушы қолжетімсіз',
                      'Recipient unavailable')
                  : s.t('Отправитель недоступен', 'Жіберуші қолжетімсіз',
                      'Sender unavailable'))),
      ]),
    ));
  }

  Future<void> _progress(String id, String action) => _load(
      () => _call('POST', '$_root/$id/progress', body: {'action': action}));
}
