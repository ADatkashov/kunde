import '../education/education_operations_screen.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../identity/auth_repository.dart';
import '../maps/kunde_maps.dart';
import '../rides/ride_strings.dart';
import '../rides/ride_widgets.dart' show rideFare;
import 'auto_work_screen.dart';
import 'gate_scan_screen.dart';
import 'leisure_work_screen.dart';
import 'delivery_work_screen.dart';
import 'food_work_screen.dart';
import 'driver_navigation_screen.dart';
import 'executor_api.dart';
import 'executor_home_widgets.dart';

class ExecutorScreen extends StatefulWidget {
  const ExecutorScreen(
      {required this.auth,
      this.checkDeliveryMode = false,
      this.mapsFactory = KundeMaps.forContext,
      super.key});

  final AuthRepository auth;
  final bool checkDeliveryMode;

  /// Creates the Maps SDK facade when the server enables it; tests replace it.
  final KundeMaps Function(BuildContext context) mapsFactory;

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
  bool _foodAvailable = false;
  bool _deliveryEnabled = false;
  bool _deliveryResume = false;
  bool _deliverySynthetic = false;
  bool _autoEnabled = false;
  bool _leisureAvailable = false;
  bool _gateAvailable = false;
  bool _educationEnabled = false;
  bool _autoResume = false;
  bool _mapsAvailable = false;
  int _tab = 0;

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
      final enabled = capabilities['deliveryExecutorEnabled'] == true;
      final food = capabilities['marketplaceEnabled'] == true &&
          capabilities['groceriesEnabled'] == true;
      final List<dynamic> shipments = enabled
          ? const []
          : await widget.auth.authorizedJson('GET', 'executor/deliveries')
              as List<dynamic>;
      if (!mounted) return;
      setState(() {
        _foodAvailable = food;
        _deliveryEnabled = enabled;
        _deliveryResume = shipments.any((row) =>
            row is Map<String, dynamic> && row['pickupAddress'] != null);
        _deliverySynthetic = capabilities['deliverySyntheticRouting'] == true;
        _mapsAvailable = capabilities['mapsEnabled'] == true;
      });
    } catch (_) {
      if (mounted && _deliveryEnabled) setState(() => _deliveryEnabled = false);
    }
    await _loadAutoMode();
  }

  /// KUNDE Auto specialist mode: offered while the server enables Auto, or while the user still has an assigned job.
  Future<void> _loadAutoMode() async {
    try {
      final capabilities = await widget.auth
          .authorizedJson('GET', 'capabilities') as Map<String, dynamic>;
      final enabled = capabilities['autoEnabled'] == true;
      var leisure = capabilities['leisureEnabled'] == true;
      if (!leisure) {
        try {
          final rows = await widget.auth.authorizedJson(
              'GET', 'executor/leisure/assignments') as List<dynamic>;
          leisure = rows.isNotEmpty;
        } on IdentityApiError {
          leisure = false;
        }
      }
      var education = capabilities['educationEnabled'] == true;
      if (!education) {
        try {
          final sessions = await widget.auth.authorizedJson(
              'GET', 'executor/education/sessions') as List<dynamic>;
          education = sessions.isNotEmpty;
        } on IdentityApiError {
          education = false;
        }
      }
      var resume = false;
      if (!enabled) {
        try {
          final jobs = await widget.auth
              .authorizedJson('GET', 'executor/auto/jobs') as List<dynamic>;
          resume = jobs.any((row) =>
              row is Map<String, dynamic> &&
              const {'ASSIGNED', 'ARRIVED', 'IN_PROGRESS'}
                  .contains(row['status']));
        } on IdentityApiError {
          resume = false;
        }
      }
      if (mounted) {
        setState(() {
          _autoEnabled = enabled;
          _autoResume = resume;
          _leisureAvailable = leisure;
          _gateAvailable = capabilities['eventsEnabled'] == true;
          _educationEnabled = education;
        });
      }
    } catch (_) {
      if (mounted && _autoEnabled) setState(() => _autoEnabled = false);
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

  Future<void> _navigate(ExecutorTrip trip) async {
    final target = trip.navigationTarget;
    if (target == null || !_mapsAvailable) return;
    final s = RideStrings(context);
    final maps = widget.mapsFactory(context);
    try {
      await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => DriverNavigationScreen(
          maps: maps,
          target: target,
          title: trip.status == 'IN_PROGRESS'
              ? s.t('К пункту назначения', 'Межелі орынға', 'To destination')
              : s.t('К пассажиру', 'Жолаушыға', 'To passenger'),
        ),
      ));
    } finally {
      maps.close();
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
    final active = _trips.where((trip) => trip.nextStep != null);
    final failure = _failure ?? _locationFailure;
    return Scaffold(
      appBar: AppBar(
        title: const Text('KUNDE Executor'),
        actions: [
          if (_foodAvailable)
            IconButton(
              key: const Key('executor-food'),
              icon: const Icon(Icons.shopping_basket_outlined),
              tooltip:
                  s.t('Заказы магазинов', 'Дүкен тапсырыстары', 'Store orders'),
              onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                      builder: (_) => FoodWorkScreen(auth: widget.auth))),
            ),
          if (_deliveryEnabled || _deliveryResume)
            IconButton(
              icon: const Icon(Icons.inventory_2_outlined),
              tooltip: s.t('Режим доставки', 'Жеткізу режимі', 'Delivery mode'),
              onPressed: () =>
                  Navigator.of(context).push<void>(MaterialPageRoute(
                builder: (_) => DeliveryWorkScreen(
                  auth: widget.auth,
                  synthetic: _deliverySynthetic,
                  intakeEnabled: _deliveryEnabled,
                  mapsFactory: _mapsAvailable ? widget.mapsFactory : null,
                ),
              )),
            ),
          if (_gateAvailable)
            IconButton(
              icon: const Icon(Icons.qr_code_scanner_rounded),
              tooltip: s.t('Проверка билетов (События)',
                  'Билеттерді тексеру (Іс-шаралар)', 'Ticket check (Events)'),
              onPressed: () =>
                  Navigator.of(context).push<void>(MaterialPageRoute(
                builder: (_) => GateScanScreen(auth: widget.auth),
              )),
            ),
          if (_educationEnabled)
            IconButton(
              icon: const Icon(Icons.school_outlined),
              tooltip: s.t('Мои занятия', 'Сабақтарым', 'My classes'),
              onPressed: () =>
                  Navigator.of(context).push<void>(MaterialPageRoute(
                builder: (_) => EducationOperationsScreen(auth: widget.auth),
              )),
            ),
          if (_leisureAvailable)
            IconButton(
              icon: const Icon(Icons.confirmation_number_outlined),
              tooltip: s.t(
                  'Досуг (гид, ведущий, инструктор)',
                  'Демалыс (гид, жүргізуші, нұсқаушы)',
                  'Leisure (guide, host, instructor)'),
              onPressed: () =>
                  Navigator.of(context).push<void>(MaterialPageRoute(
                builder: (_) => LeisureWorkScreen(auth: widget.auth),
              )),
            ),
          if (_autoEnabled || _autoResume)
            IconButton(
              icon: const Icon(Icons.build_circle_outlined),
              tooltip: s.t('Авто-специалист', 'Авто маман', 'Auto specialist'),
              onPressed: () =>
                  Navigator.of(context).push<void>(MaterialPageRoute(
                builder: (_) => AutoWorkScreen(
                  auth: widget.auth,
                  synthetic: _deliverySynthetic,
                  intakeEnabled: _autoEnabled,
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
          if (profile != null)
            ...switch (_tab) {
              1 => _ordersTab(s),
              2 => _incomeTab(s, profile),
              3 => _profileTab(s, profile),
              _ => _homeTab(s, profile, active.toList()),
            },
        ],
      ),
      bottomNavigationBar: profile == null
          ? null
          : NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (index) => setState(() => _tab = index),
              destinations: [
                NavigationDestination(
                    icon: const Icon(Icons.home_outlined),
                    selectedIcon: const Icon(Icons.home_rounded),
                    label: s.t('Главная', 'Басты', 'Home')),
                NavigationDestination(
                    icon: const Icon(Icons.receipt_long_outlined),
                    selectedIcon: const Icon(Icons.receipt_long_rounded),
                    label: s.t('Заказы', 'Тапсырыстар', 'Orders')),
                NavigationDestination(
                    icon: const Icon(Icons.account_balance_wallet_outlined),
                    selectedIcon:
                        const Icon(Icons.account_balance_wallet_rounded),
                    label: s.t('Доход', 'Табыс', 'Income')),
                NavigationDestination(
                    icon: const Icon(Icons.person_outline_rounded),
                    selectedIcon: const Icon(Icons.person_rounded),
                    label: s.t('Профиль', 'Профиль', 'Profile')),
              ],
            ),
    );
  }

  Widget _driverHeader(RideStrings s, ExecutorProfile profile) {
    final vehicle = profile.vehicle;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        const CircleAvatar(child: Icon(Icons.person_rounded)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(profile.name,
                  style:
                      text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              Text(
                  vehicle == null
                      ? _status(s, profile.status)
                      : '${vehicle['description']} · ${vehicle['plate']}',
                  style: text.bodySmall),
            ],
          ),
        ),
        if (!profile.approved)
          Chip(
              label: Text(_status(
                  s,
                  profile.status != 'APPROVED'
                      ? profile.status
                      : (vehicle?['status'] as String? ?? 'PENDING')))),
      ]),
    );
  }

  Widget _vehicleForm(RideStrings s) => Form(
        key: _form,
        child: Column(
          children: [
            _field(_description,
                s.t('Модель автомобиля', 'Көлік үлгісі', 'Vehicle model'), s,
                max: 100),
            _field(_plate, s.t('Госномер', 'Мемлекеттік нөмір', 'Plate'), s,
                max: 16, pattern: RegExp(r'^[A-Za-z0-9]{3,16}$')),
            DropdownButtonFormField<String>(
              initialValue: _rideClass,
              items: [
                for (final item in ['ECONOMY', 'COMFORT', 'BUSINESS'])
                  DropdownMenuItem(value: item, child: Text(s.rideClass(item))),
              ],
              onChanged:
                  _busy ? null : (value) => setState(() => _rideClass = value!),
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
              child:
                  Text(s.t('Добавить автомобиль', 'Көлік қосу', 'Add vehicle')),
            ),
          ],
        ),
      );

  List<Widget> _homeTab(
      RideStrings s, ExecutorProfile profile, List<ExecutorTrip> active) {
    final summary = ExecutorDaySummary.of(_trips, DateTime.now());
    final finished = _trips.where((trip) => trip.nextStep == null).toList();
    final pending = !profile.approved;
    return [
      ExecutorOnlineBanner(
        online: profile.online,
        onChanged: _busy || pending ? null : _setOnline,
        hint: pending
            ? s.t(
                'Доступно после проверки профиля и автомобиля.',
                'Профиль мен көлік тексерілгеннен кейін қолжетімді.',
                'Available after profile and vehicle review.')
            : s.t(
                'Положение передаётся только при открытом приложении.',
                'Орналасқан жер қолданба ашық кезде ғана жіберіледі.',
                'Location is shared only while the app is open.'),
      ),
      if (profile.online && !_sharing)
        OutlinedButton(
          onPressed: _busy ? null : () => _setOnline(true),
          child: Text(s.t('Разрешить геопозицию', 'Орналасуға рұқсат беру',
              'Enable location')),
        ),
      _driverHeader(s, profile),
      if (profile.vehicle == null) _vehicleForm(s),
      ExecutorEarningsCard(summary: summary, rating: profile.rating),
      const SizedBox(height: 16),
      ExecutorPrimaryButton(
        label: s.t('Получить заказ', 'Тапсырыс алу', 'Get an order'),
        onPressed: _busy || pending
            ? null
            : () => profile.online ? _load() : _setOnline(true),
      ),
      const SizedBox(height: 8),
      for (final offer
          in _offers.where((offer) => offer.expiresAt.isAfter(DateTime.now())))
        Card(
          child: ListTile(
            title: Text(offer.synthetic
                ? s.synthetic
                : s.t('Предложение поездки', 'Сапар ұсынысы', 'Ride offer')),
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
            subtitle: Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () =>
                          _load(() => _api.advance(trip.id, trip.nextStep!)),
                  child: Text(_actionName(s, trip.nextStep!)),
                ),
                if (_mapsAvailable && trip.navigationTarget != null)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.navigation_outlined),
                    onPressed: _busy ? null : () => _navigate(trip),
                    label: Text(s.t('Навигатор', 'Навигатор', 'Navigate')),
                  ),
              ],
            ),
          ),
        ),
      const SizedBox(height: 8),
      ExecutorMenuTile(
          icon: Icons.assignment_outlined,
          title: s.t('Мои поездки', 'Менің сапарларым', 'My rides'),
          onTap: () => setState(() => _tab = 1)),
      ExecutorMenuTile(
          icon: Icons.account_balance_wallet_outlined,
          title: s.t(
              'Доход и выплаты', 'Табыс және төлемдер', 'Income and payouts'),
          onTap: () => setState(() => _tab = 2)),
      ExecutorMenuTile(
          icon: Icons.bar_chart_rounded,
          title: s.t('Статистика', 'Статистика', 'Statistics'),
          onTap: () => _showStatistics(s, profile, summary)),
      ExecutorMenuTile(
          icon: Icons.support_agent_rounded,
          title: s.t('Поддержка', 'Қолдау', 'Support'),
          onTap: () => _showNotice(
              s.t('Поддержка', 'Қолдау', 'Support'),
              s.t(
                  'Чат поддержки для водителей ещё не подключён. Обратитесь к вашему парку или оператору.',
                  'Жүргізушілерге арналған қолдау чаты әлі қосылмаған. Паркке немесе операторға хабарласыңыз.',
                  'Driver support chat is not connected yet. Contact your fleet or operator.'))),
      if (finished.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(s.history, style: Theme.of(context).textTheme.titleLarge),
        for (final trip in finished.take(3)) _tripTile(s, trip),
      ],
    ];
  }

  Widget _tripTile(RideStrings s, ExecutorTrip trip) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(trip.synthetic
            ? '${s.synthetic} · ${s.status(trip.status)}'
            : s.status(trip.status)),
        subtitle: Text(MaterialLocalizations.of(context)
            .formatShortDate(trip.createdAt.toLocal())),
        trailing: trip.fareKzt == null || trip.synthetic
            ? null
            : Text(rideFare(trip.fareKzt!),
                style: const TextStyle(fontWeight: FontWeight.w700)),
      );

  List<Widget> _ordersTab(RideStrings s) => [
        Text(s.t('Мои поездки', 'Менің сапарларым', 'My rides'),
            style: Theme.of(context).textTheme.headlineSmall),
        if (_trips.isEmpty)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(s.noRides)),
        for (final trip in _trips) _tripTile(s, trip),
      ];

  List<Widget> _incomeTab(RideStrings s, ExecutorProfile profile) {
    final summary = ExecutorDaySummary.of(_trips, DateTime.now());
    return [
      Text(s.t('Доход и выплаты', 'Табыс және төлемдер', 'Income and payouts'),
          style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 12),
      ExecutorEarningsCard(summary: summary, rating: profile.rating),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(s.t('За 7 дней', '7 күн ішінде', 'Last 7 days')),
        trailing: Text(rideFare(summary.weekFare),
            key: const Key('executor-week-fare'),
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      Text(
          s.t(
              'Суммы — тарифная оценка завершённых поездок за последние 50 заказов. Тестовые маршруты не учитываются. Онлайн-выплаты ещё не подключены.',
              'Сомалар — соңғы 50 тапсырыстағы аяқталған сапарлардың тариф бағасы. Сынақ бағыттары есепке алынбайды. Онлайн төлемдер әлі қосылмаған.',
              'Amounts are tariff estimates of completed rides within the last 50 orders. Test routes are excluded. Online payouts are not connected yet.'),
          style: Theme.of(context).textTheme.bodySmall),
    ];
  }

  List<Widget> _profileTab(RideStrings s, ExecutorProfile profile) => [
        _driverHeader(s, profile),
        if (profile.vehicle == null) _vehicleForm(s),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.logout),
          onPressed: _busy ? null : _logout,
          label: Text(s.t('Выйти', 'Шығу', 'Sign out')),
        ),
      ];

  void _showStatistics(
      RideStrings s, ExecutorProfile profile, ExecutorDaySummary summary) {
    _showNotice(
      s.t('Статистика', 'Статистика', 'Statistics'),
      '${s.t('Завершено', 'Аяқталды', 'Completed')}: ${summary.completed}\n'
      '${s.t('Отменено', 'Бас тартылды', 'Cancelled')}: ${summary.cancelled}\n'
      '${s.t('Рейтинг', 'Рейтинг', 'Rating')}: ${profile.rating == null ? '—' : profile.rating!.toStringAsFixed(profile.rating! % 1 == 0 ? 0 : 2)}'
      '${profile.ratings == 0 ? '' : ' (${profile.ratings})'}',
    );
  }

  void _showNotice(String title, String message) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(message),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocationAccessFailure implements Exception {
  const _LocationAccessFailure();
}
