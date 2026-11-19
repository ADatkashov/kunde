import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../identity/auth_repository.dart';
import '../rides/ride_strings.dart';
import 'delivery_work_screen.dart';
import 'executor_api.dart';

class ExecutorScreen extends StatefulWidget {
  const ExecutorScreen(
      {required this.auth, this.checkDeliveryMode = false, super.key});

  final AuthRepository auth;
  final bool checkDeliveryMode;

  @override
  State<ExecutorScreen> createState() => _ExecutorScreenState();
}

class _ExecutorScreenState extends State<ExecutorScreen>
    with WidgetsBindingObserver {
  late final _api = ExecutorApi(widget.auth);
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _plate = TextEditingController();
  ExecutorProfile? _profile;
  List<ExecutorOffer> _offers = [];
  List<ExecutorTrip> _trips = [];
  Timer? _refreshTimer;
  StreamSubscription<Position>? _positions;
  bool _locationBusy = false;
  bool _loaded = false;
  bool _busy = false;
  bool _foreground = true;
  bool _sharing = false;
  String _rideClass = 'ECONOMY';
  String? _failure;
  String? _locationFailure;
  bool _deliveryEnabled = false;
  bool _deliverySynthetic = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshTimer = Timer.periodic(const Duration(seconds: 7), (_) {
      if (_foreground && _loaded && _profile != null) unawaited(_load());
    });
    unawaited(_load());
    if (widget.checkDeliveryMode) unawaited(_loadModes());
  }

  Future<void> _loadModes() async {
    try {
      final capabilities = await widget.auth
          .authorizedJson('GET', 'capabilities') as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _deliveryEnabled = capabilities['deliveryExecutorEnabled'] == true;
        _deliverySynthetic = capabilities['deliverySyntheticRouting'] == true;
      });
    } catch (_) {
      if (mounted && _deliveryEnabled) setState(() => _deliveryEnabled = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      unawaited(_stopLocation());
    } else {
      unawaited(_load());
      if (widget.checkDeliveryMode) unawaited(_loadModes());
    }
  }

  Future<void> _load([Future<void> Function()? action]) async {
    if (_busy || !mounted) return;
    setState(() => _busy = true);
    try {
      if (action != null) await action();
      if (!mounted || !widget.auth.authenticated) return;
      final profile = await _api.profile();
      final offers =
          profile?.online == true ? await _api.offers() : <ExecutorOffer>[];
      final trips = profile == null ? <ExecutorTrip>[] : await _api.trips();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _offers = offers;
        _trips = trips;
        _loaded = true;
        _failure = null;
      });
      if (profile?.online != true) {
        _sharing = false;
        await _stopLocation();
      } else if (_sharing && _foreground && _positions == null) {
        _listenForLocation();
      }
    } on _LocationAccessFailure {
      if (mounted) setState(() => _failure = 'LOCATION_PERMISSION');
    } on IdentityApiError catch (error) {
      if (mounted) setState(() => _failure = error.code ?? 'UNKNOWN');
    } catch (_) {
      if (mounted) setState(() => _failure = 'UNKNOWN');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setOnline(bool enabled) => _load(() async {
        if (enabled) {
          if (!await Geolocator.isLocationServiceEnabled()) {
            throw const _LocationAccessFailure();
          }
          var permission = await Geolocator.checkPermission();
          if (permission == LocationPermission.denied) {
            permission = await Geolocator.requestPermission();
          }
          if (permission != LocationPermission.whileInUse &&
              permission != LocationPermission.always) {
            throw const _LocationAccessFailure();
          }
          if (!mounted || !_foreground) return;
          await _api.online(true);
          _sharing = true;
        } else {
          _sharing = false;
          await _stopLocation();
          await _api.online(false);
        }
      });

  void _listenForLocation() {
    _positions = Geolocator.getPositionStream(
      locationSettings:
          !kIsWeb && defaultTargetPlatform == TargetPlatform.android
              ? AndroidSettings(
                  accuracy: LocationAccuracy.high,
                  intervalDuration: const Duration(seconds: 10),
                )
              : const LocationSettings(accuracy: LocationAccuracy.high),
    ).listen(
      (position) async {
        if (_locationBusy ||
            !_sharing ||
            !_foreground ||
            !mounted ||
            DateTime.now().difference(position.timestamp) >
                const Duration(seconds: 30)) {
          return;
        }
        _locationBusy = true;
        try {
          await _api.location(position.latitude, position.longitude);
          if (mounted && _locationFailure != null) {
            setState(() => _locationFailure = null);
          }
        } on IdentityApiError catch (error) {
          if (error.status == 404 ||
              error.status == 403 ||
              error.status == 409) {
            _sharing = false;
            await _stopLocation();
          }
          if (mounted && error.status != 429) {
            setState(() => _locationFailure = 'LOCATION_SEND');
          }
        } catch (_) {
          if (mounted) setState(() => _locationFailure = 'LOCATION_SEND');
        } finally {
          _locationBusy = false;
        }
      },
      onError: (Object error) {
        if (mounted) setState(() => _locationFailure = 'LOCATION_SEND');
        unawaited(_stopLocation());
      },
    );
  }

  Future<void> _stopLocation() async {
    final positions = _positions;
    _positions = null;
    await positions?.cancel();
  }

  Future<void> _logout() async {
    _sharing = false;
    await _stopLocation();
    if (!mounted) return;
    try {
      if (_profile?.online == true) await _api.online(false);
    } catch (_) {
      // The position stream is already stopped even if offline mode is unavailable.
    }
    if (mounted) await widget.auth.logout();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    unawaited(_stopLocation());
    _name.dispose();
    _description.dispose();
    _plate.dispose();
    super.dispose();
  }

  String _status(RideStrings s, String status) => switch (status) {
        'APPROVED' => s.t('Одобрено', 'Мақұлданды', 'Approved'),
        'BLOCKED' => s.t('Заблокировано', 'Бұғатталды', 'Blocked'),
        _ => s.t('На проверке', 'Тексерілуде', 'Under review'),
      };

  String _actionName(RideStrings s, String key) => switch (key) {
        'DEPART' => s.t('Выехать', 'Жолға шығу', 'Depart'),
        'ARRIVE' => s.t('Я на месте', 'Келдім', 'I have arrived'),
        'START' => s.t('Начать поездку', 'Сапарды бастау', 'Start ride'),
        _ => s.t('Завершить', 'Аяқтау', 'Complete'),
      };

  String _error(RideStrings s, String code) => switch (code) {
        'RIDES_EXECUTOR_UNAVAILABLE' => s.t(
            'Режим водителя недоступен.',
            'Жүргізуші режимі қолжетімсіз.',
            'Driver mode is unavailable.',
          ),
        'LOCATION_PERMISSION' => s.t(
            'Разрешите геопозицию при использовании приложения.',
            'Қолданбаны пайдаланғанда орналасуға рұқсат беріңіз.',
            'Allow location while using the app.',
          ),
        'LOCATION_SEND' => s.t(
            'Местоположение не отправлено.',
            'Орналасқан жер жіберілмеді.',
            'Location could not be sent.',
          ),
        _ => s.error,
      };

  Widget _field(TextEditingController controller, String label, RideStrings s,
      {int max = 80, Pattern? pattern}) {
    return TextFormField(
      controller: controller,
      maxLength: max,
      enabled: !_busy,
      decoration: InputDecoration(labelText: label),
      validator: (value) {
        final text = value?.trim() ?? '';
        if (text.isEmpty || (pattern is RegExp && !pattern.hasMatch(text))) {
          return s.t('Проверьте поле', 'Өрісті тексеріңіз', 'Check this field');
        }
        return null;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    final profile = _profile;
    final vehicle = profile?.vehicle;
    final active = _trips.where((trip) => trip.nextStep != null);
    final failure = _failure ?? _locationFailure;
    return Scaffold(
      appBar: AppBar(
        title: const Text('KUNDE Executor'),
        actions: [
          if (_deliveryEnabled)
            IconButton(
              icon: const Icon(Icons.inventory_2_outlined),
              tooltip: s.t('Режим доставки', 'Жеткізу режимі', 'Delivery mode'),
              onPressed: () =>
                  Navigator.of(context).push<void>(MaterialPageRoute(
                builder: (_) => DeliveryWorkScreen(
                  auth: widget.auth,
                  synthetic: _deliverySynthetic,
                ),
              )),
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: s.t('Выйти', 'Шығу', 'Sign out'),
            onPressed: _busy ? null : _logout,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (failure != null)
            Semantics(
              liveRegion: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_error(s, failure)),
                  TextButton(
                      onPressed: _busy ? null : () => _load(),
                      child: Text(s.retry)),
                ],
              ),
            ),
          if (_loaded && profile == null)
            Form(
              key: _form,
              child: Column(
                children: [
                  _field(_name,
                      s.t('Имя водителя', 'Жүргізуші аты', 'Driver name'), s),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () {
                            if (_form.currentState!.validate()) {
                              unawaited(_load(
                                  () => _api.register(_name.text.trim())));
                            }
                          },
                    child: Text(s.t('Отправить на проверку', 'Тексеруге жіберу',
                        'Submit for review')),
                  ),
                ],
              ),
            ),
          if (profile != null) ...[
            Card(
                child: ListTile(
                    title: Text(profile.name),
                    subtitle: Text(_status(s, profile.status)))),
            if (vehicle != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.directions_car_outlined),
                  title:
                      Text('${vehicle['description']} · ${vehicle['plate']}'),
                  subtitle: Text(_status(s, vehicle['status'] as String)),
                ),
              ),
            if (vehicle == null)
              Form(
                key: _form,
                child: Column(
                  children: [
                    _field(
                        _description,
                        s.t('Модель автомобиля', 'Көлік үлгісі',
                            'Vehicle model'),
                        s,
                        max: 100),
                    _field(_plate,
                        s.t('Госномер', 'Мемлекеттік нөмір', 'Plate'), s,
                        max: 16, pattern: RegExp(r'^[A-Za-z0-9]{3,16}$')),
                    DropdownButtonFormField<String>(
                      initialValue: _rideClass,
                      items: [
                        for (final item in ['ECONOMY', 'COMFORT', 'BUSINESS'])
                          DropdownMenuItem(
                              value: item, child: Text(s.rideClass(item))),
                      ],
                      onChanged: _busy
                          ? null
                          : (value) => setState(() => _rideClass = value!),
                    ),
                    FilledButton(
                      onPressed: _busy
                          ? null
                          : () {
                              if (_form.currentState!.validate()) {
                                unawaited(_load(() => _api.vehicle(
                                    _description.text.trim(),
                                    _plate.text.trim(),
                                    _rideClass)));
                              }
                            },
                      child: Text(s.t(
                          'Добавить автомобиль', 'Көлік қосу', 'Add vehicle')),
                    ),
                  ],
                ),
              ),
            SwitchListTile(
              title: Text(s.t('На линии', 'Желіде', 'Online')),
              subtitle: Text(s.t(
                  'Положение передаётся только при открытом приложении.',
                  'Орналасқан жер қолданба ашық кезде ғана жіберіледі.',
                  'Location is shared only while the app is open.')),
              value: profile.online,
              onChanged: _busy || !profile.approved ? null : _setOnline,
            ),
            if (profile.online && !_sharing)
              OutlinedButton(
                onPressed: _busy ? null : () => _setOnline(true),
                child: Text(s.t('Разрешить геопозицию',
                    'Орналасуға рұқсат беру', 'Enable location')),
              ),
            for (final offer in _offers
                .where((offer) => offer.expiresAt.isAfter(DateTime.now())))
              Card(
                child: ListTile(
                  title: Text(offer.synthetic
                      ? s.synthetic
                      : s.t('Предложение поездки', 'Сапар ұсынысы',
                          'Ride offer')),
                  subtitle: Wrap(
                    spacing: 8,
                    children: [
                      FilledButton(
                        onPressed: _busy
                            ? null
                            : () => _load(() => _api.respond(offer.id, true)),
                        child: Text(s.t('Принять', 'Қабылдау', 'Accept')),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _load(() => _api.respond(offer.id, false)),
                        child: Text(s.t('Отклонить', 'Қабылдамау', 'Decline')),
                      ),
                    ],
                  ),
                ),
              ),
            for (final trip in active)
              Card(
                child: ListTile(
                  title: Text(trip.synthetic
                      ? '${s.synthetic} · ${s.status(trip.status)}'
                      : s.status(trip.status)),
                  subtitle: FilledButton(
                    onPressed: _busy
                        ? null
                        : () =>
                            _load(() => _api.advance(trip.id, trip.nextStep!)),
                    child: Text(_actionName(s, trip.nextStep!)),
                  ),
                ),
              ),
            if (_trips.any((trip) => trip.nextStep == null))
              Text(s.history, style: Theme.of(context).textTheme.titleLarge),
            for (final trip in _trips.where((trip) => trip.nextStep == null))
              ListTile(
                title: Text(trip.synthetic
                    ? '${s.synthetic} · ${s.status(trip.status)}'
                    : s.status(trip.status)),
                subtitle: Text(MaterialLocalizations.of(context)
                    .formatShortDate(trip.createdAt.toLocal())),
              ),
          ],
        ],
      ),
    );
  }
}

class _LocationAccessFailure implements Exception {
  const _LocationAccessFailure();
}
