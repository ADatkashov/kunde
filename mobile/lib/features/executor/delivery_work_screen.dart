import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'package:kunde_maps_sdk/kunde_maps_sdk.dart';

import '../delivery/delivery_strings.dart';
import '../identity/auth_repository.dart';
import '../maps/kunde_maps.dart';
import 'driver_navigation_screen.dart';

class DeliveryWorkScreen extends StatefulWidget {
  const DeliveryWorkScreen(
      {required this.auth,
      required this.synthetic,
      this.intakeEnabled = true,
      this.readPosition,
      this.mapsFactory,
      super.key});

  final AuthRepository auth;
  final bool synthetic;
  final bool intakeEnabled;
  final Future<({double latitude, double longitude})> Function()? readPosition;

  /// Creates the Maps SDK facade for courier navigation. Null (the server did not enable Maps) hides the Navigate button.
  final KundeMaps Function(BuildContext context)? mapsFactory;

  @override
  State<DeliveryWorkScreen> createState() => _DeliveryWorkScreenState();
}

class _DeliveryWorkScreenState extends State<DeliveryWorkScreen>
    with WidgetsBindingObserver {
  static const _trackable = {
    'COURIER_ASSIGNED',
    'COURIER_ARRIVING',
    'COURIER_ARRIVED',
    'PICKED_UP',
    'IN_TRANSIT',
    'RETURNING',
  };
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
  Timer? _locationTimer;
  Future<void>? _positionUpdate;
  String? _sharingId;
  bool _sharingFailed = false;
  bool _clearingLocation = false;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    unawaited(_load());
    _poll = Timer.periodic(const Duration(seconds: 7), (_) {
      if (ModalRoute.of(context)?.isCurrent == true && _profile != null) {
        unawaited(_load());
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _locationTimer?.cancel();
      _locationTimer = null;
    } else {
      _scheduleLocation();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _locationTimer?.cancel();
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
      final offers = widget.intakeEnabled && profile?['online'] == true
          ? (await _call('GET', '$_root/offers') as List)
              .cast<Map<String, dynamic>>()
          : <Map<String, dynamic>>[];
      final shipments = profile == null
          ? <Map<String, dynamic>>[]
          : (await _call('GET', _root) as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      if (_sharingId != null &&
          !shipments.any((row) =>
              row['id'] == _sharingId && _trackable.contains(row['status']))) {
        _clearSharingState();
      }
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

  Future<({double latitude, double longitude})> _readPosition(
      {bool requestPermission = false}) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw IdentityUnavailable();
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && requestPermission) {
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
    return (latitude: position.latitude, longitude: position.longitude);
  }

  Future<void> _sendLocation({required bool fixture, String? shipmentId}) =>
      _load(() async {
        final point = fixture
            ? (latitude: 43.24, longitude: 76.92)
            : await (widget.readPosition?.call() ??
                _readPosition(requestPermission: true));
        if (!mounted) return;
        await _pushPosition(shipmentId, point);
      });

  Future<dynamic> _pushPosition(
          String? shipmentId, ({double latitude, double longitude}) point) =>
      _call(
        'PUT',
        shipmentId == null ? '$_root/location' : '$_root/$shipmentId/location',
        body: {'latitude': point.latitude, 'longitude': point.longitude},
        expected: {204},
      );

  void _startSharing(String id) {
    setState(() {
      _sharingId = id;
      _sharingFailed = false;
    });
    _tickLocation(requestPermission: true);
  }

  void _scheduleLocation() {
    if (_sharingId == null || !_foreground || _locationTimer != null) return;
    _locationTimer = Timer(const Duration(seconds: 7), () {
      _locationTimer = null;
      _tickLocation();
    });
  }

  void _tickLocation({bool requestPermission = false}) {
    final id = _sharingId;
    if (id == null || !_foreground || _positionUpdate != null) return;
    _positionUpdate = _publishPosition(id, requestPermission: requestPermission)
        .whenComplete(() {
      _positionUpdate = null;
      if (mounted) _scheduleLocation();
    });
  }

  Future<void> _publishPosition(String id,
      {required bool requestPermission}) async {
    try {
      final point = await (widget.readPosition?.call() ??
          _readPosition(requestPermission: requestPermission));
      if (!mounted || !_foreground || _sharingId != id) return;
      await _pushPosition(id, point);
      if (mounted && _sharingId == id && _sharingFailed) {
        setState(() => _sharingFailed = false);
      }
    } on IdentityApiError catch (error) {
      if (!mounted || _sharingId != id) return;
      if (error.status == 403 || error.status == 404) {
        setState(() {
          _clearSharingState();
          _error = true;
        });
      } else {
        setState(() => _sharingFailed = true);
      }
    } catch (_) {
      if (mounted && _sharingId == id) {
        setState(() => _sharingFailed = true);
      }
    }
  }

  void _clearSharingState() {
    _locationTimer?.cancel();
    _locationTimer = null;
    _sharingId = null;
    _sharingFailed = false;
  }

  Future<void> _stopSharing(String id) async {
    setState(() {
      _clearSharingState();
      _clearingLocation = true;
    });
    try {
      await _positionUpdate;
      if (mounted) {
        await _call('DELETE', '$_root/$id/location', expected: {204});
      }
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _clearingLocation = false);
    }
  }

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
            if (widget.intakeEnabled && _loaded && profile == null) ...[
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
            if (widget.intakeEnabled && approval == 'APPROVED')
              SwitchListTile(
                title: Text(s.t('Готов принимать заказы',
                    'Тапсырыс қабылдауға дайынмын', 'Available for offers')),
                value: online,
                onChanged: _busy
                    ? null
                    : (value) => _load(() => _call('PUT', '$_root/availability',
                        body: {'online': value})),
              ),
            if (widget.intakeEnabled && online) ...[
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
        if (widget.mapsFactory != null && _target(shipment) != null)
          OutlinedButton.icon(
              icon: const Icon(Icons.navigation_outlined),
              onPressed: _busy ? null : () => _navigate(shipment, s),
              label: Text(s.t('Навигатор', 'Навигатор', 'Navigate'))),
        if (_trackable.contains(status) && !widget.synthetic)
          _sharingId == id
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      liveRegion: true,
                      child: Text(_sharingFailed
                          ? s.t(
                              'Нет GPS или связи. Повторяем при подключении.',
                              'GPS немесе байланыс жоқ. Қосылғанда қайталаймыз.',
                              'GPS or network unavailable. Retrying.')
                          : s.t(
                              'Передаём точку, пока приложение открыто',
                              'Қолданба ашық кезде орынды жібереміз',
                              'Sharing while the app is open')),
                    ),
                    TextButton(
                      onPressed: _busy ? null : () => _stopSharing(id),
                      child: Text(s.t('Остановить передачу', 'Жіберуді тоқтату',
                          'Stop sharing location')),
                    ),
                  ],
                )
              : OutlinedButton(
                  onPressed: _busy || _clearingLocation || _sharingId != null
                      ? null
                      : () => _startSharing(id),
                  child: Text(s.t(
                    'Показывать мою точку отправителю',
                    'Орнымды жіберушіге көрсету',
                    'Share live location with sender',
                  )),
                ),
        if (_trackable.contains(status) && widget.synthetic)
          Wrap(spacing: 8, children: [
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _sendLocation(fixture: false, shipmentId: id),
              child: Text(s.t('Передать точку отправителю',
                  'Жіберушіге орынды жіберу', 'Share location with sender')),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _load(() =>
                      _call('DELETE', '$_root/$id/location', expected: {204})),
              child: Text(s.t('Скрыть точку', 'Орнын жасыру', 'Hide location')),
            ),
          ]),
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

  /// Where to guide the courier now: to the sender before pickup (and back to
  /// the sender on return), to the recipient while carrying the parcel.
  static GeoPoint? _target(Map<String, dynamic> shipment) {
    final key = switch (shipment['status']) {
      'COURIER_ASSIGNED' || 'COURIER_ARRIVING' || 'RETURNING' => 'pickup',
      'PICKED_UP' || 'IN_TRANSIT' => 'destination',
      _ => null,
    };
    final point = key == null ? null : shipment[key];
    if (point is! Map<String, dynamic>) return null;
    try {
      return GeoPoint.parse(point['latitude'], point['longitude']);
    } on FormatException {
      return null;
    }
  }

  Future<void> _navigate(
      Map<String, dynamic> shipment, DeliveryStrings s) async {
    final target = _target(shipment);
    final factory = widget.mapsFactory;
    if (target == null || factory == null) return;
    final maps = factory(context);
    try {
      await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => DriverNavigationScreen(
          maps: maps,
          target: target,
          title: shipment['status'] == 'RETURNING' ||
                  shipment['status'] == 'COURIER_ASSIGNED' ||
                  shipment['status'] == 'COURIER_ARRIVING'
              ? s.t('К отправителю', 'Жіберушіге', 'To sender')
              : s.t('К получателю', 'Алушыға', 'To recipient'),
        ),
      ));
    } finally {
      maps.close();
    }
  }

  Future<void> _progress(String id, String action) => _load(
      () => _call('POST', '$_root/$id/progress', body: {'action': action}));
}
