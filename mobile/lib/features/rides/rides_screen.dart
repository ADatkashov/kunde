import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:kunde_design/kunde_design.dart';
import 'package:kunde_maps_sdk/kunde_maps_sdk.dart';

import '../identity/auth_repository.dart';
import '../identity/support_panel.dart';
import '../maps/kunde_maps.dart';
import 'ride_api.dart';
import 'ride_map_panels.dart';
import 'ride_strings.dart';
import 'ride_widgets.dart';

class RidesScreen extends StatefulWidget {
  const RidesScreen({required this.api, this.maps, super.key});

  final RideApi api;

  /// Present only when the server enables the KUNDE Maps provider; null keeps the list-based address flow.
  final KundeMaps? maps;

  @override
  State<RidesScreen> createState() => _RidesScreenState();
}

class _RidesScreenState extends State<RidesScreen> {
  /// Classes the map flow prices at once. A class the server has no tariff for
  /// answers `RIDE_CLASS_UNAVAILABLE` and is simply not shown.
  static const _baseClasses = ['ECONOMY', 'COMFORT', 'BUSINESS'];
  static const _allClasses = [..._baseClasses, 'MINIVAN'];

  RideAddress? _pickup;
  RideAddress? _destination;
  String _rideClass = 'ECONOMY';
  RideQuote? _quote;
  String? _key;
  bool _busy = false;
  String? _error;

  // Map flow only: one server quote per class for the current pair of points.
  Map<String, RideQuote> _quotes = const {};
  final Map<String, String> _keys = {};
  bool _quoting = false;
  bool _quoted = false;
  int _quoteRun = 0;

  RideApi get _api => widget.api;

  @override
  void initState() {
    super.initState();
    if (widget.maps != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(_locateStart()),
      );
    }
  }

  void _invalidateQuote() {
    _quote = null;
    _key = null;
    _error = null;
    _quotes = const {};
    _keys.clear();
    _quoted = false;
  }

  /// Like the reference: the pickup starts at "My location". The device
  /// position is used for this screen only; without it the user picks a point.
  Future<void> _locateStart() async {
    final maps = widget.maps;
    if (maps == null || !mounted || _pickup != null) return;
    final label = RideStrings(context).myLocation;
    final GeoPoint? point;
    try {
      point = await maps.geolocation.currentPoint();
    } catch (_) {
      return;
    }
    if (point == null || !mounted || _pickup != null) return;
    final here = point;
    setState(() {
      _pickup = RideAddress(label, {
        'latitude': here.lat,
        'longitude': here.lon,
      });
      _invalidateQuote();
    });
    if (_destination != null) unawaited(_quoteAll());
  }

  /// Prices every class for the current points, in parallel. Prices are the
  /// server's quotes; the device computes nothing.
  Future<void> _quoteAll({String? notice}) async {
    final pickup = _pickup;
    final destination = _destination;
    if (pickup == null || destination == null) return;
    final run = ++_quoteRun;
    setState(() {
      _quoting = true;
      _quoted = false;
      _quotes = const {};
      _keys.clear();
      _quote = null;
      _key = null;
      _error = notice;
    });
    final found = <String, RideQuote>{};
    Object? failure;
    await Future.wait([
      for (final value in _allClasses)
        () async {
          try {
            found[value] = await _api.quote(pickup, destination, value);
          } on IdentityApiError catch (error) {
            if (error.code != 'RIDE_CLASS_UNAVAILABLE') failure = error;
          } catch (error) {
            failure = error;
          }
        }(),
    ]);
    if (!mounted || run != _quoteRun) return;
    final strings = RideStrings(context);
    setState(() {
      _quoting = false;
      _quoted = true;
      _quotes = found;
      if (found.isEmpty) {
        final failed = failure;
        _error = failed is IdentityApiError && failed.status == 503
            ? strings.unavailable
            : strings.error;
        return;
      }
      if (!found.containsKey(_rideClass)) {
        _rideClass = _allClasses.firstWhere(found.containsKey);
      }
      _select(_rideClass);
    });
  }

  void _select(String value) {
    _rideClass = value;
    _quote = _quotes[value];
    _key = _quote == null ? null : _keys.putIfAbsent(value, _newKey);
  }

  static String _newKey() {
    final random = Random.secure();
    return base64Url.encode(List.generate(18, (_) => random.nextInt(256)));
  }

  /// Map flow: one tap orders the selected, already priced class.
  Future<void> _order() async {
    final strings = RideStrings(context);
    final quote = _quote;
    final key = _key;
    if (quote == null || key == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final trip = await _api.create(quote, key);
      if (!mounted) return;
      setState(_invalidateQuote);
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) =>
              _RideDetails(api: _api, trip: trip, maps: widget.maps),
        ),
      );
      // The quotes were spent by the order; price the same route again.
      if (mounted) unawaited(_quoteAll());
    } on IdentityApiError catch (error) {
      if (!mounted) return;
      if (error.code == 'RIDE_QUOTE_UNAVAILABLE') {
        unawaited(_quoteAll(notice: strings.priceUpdated));
      } else {
        setState(
          () => _error =
              error.status == 503 ? strings.unavailable : strings.error,
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = strings.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseAddress(bool pickup) async {
    final s = RideStrings(context);
    final maps = widget.maps;
    final RideAddress? address;
    if (maps != null) {
      final picked = await maps.pick(
        context,
        title: pickup ? s.pickup : s.destination,
        initial: switch (pickup ? _pickup : _destination) {
          final RideAddress current => pointOf(current),
          null => null,
        },
      );
      address =
          picked == null ? null : addressFrom(picked, maps.config.language);
    } else {
      address = await showModalBottomSheet<RideAddress>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _AddressPicker(api: _api),
      );
    }
    if (address == null || !mounted) return;
    setState(() {
      if (pickup) {
        _pickup = address;
      } else {
        _destination = address;
      }
      _invalidateQuote();
      if (maps == null || _pickup == null || _destination == null) {
        _quoteRun++;
        _quoting = false;
      }
    });
    if (maps != null && _pickup != null && _destination != null) {
      unawaited(_quoteAll());
    }
  }

  Future<void> _submit() async {
    final strings = RideStrings(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final quote = _quote;
      if (quote == null) {
        final next = await _api.quote(_pickup!, _destination!, _rideClass);
        if (!mounted) return;
        final random = Random.secure();
        setState(() {
          _quote = next;
          _key = base64Url.encode(
            List.generate(18, (_) => random.nextInt(256)),
          );
        });
      } else {
        final trip = await _api.create(quote, _key!);
        if (!mounted) return;
        setState(_invalidateQuote);
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) =>
                _RideDetails(api: _api, trip: trip, maps: widget.maps),
          ),
        );
      }
    } on IdentityApiError catch (error) {
      if (!mounted) return;
      setState(() {
        if (error.code == 'RIDE_QUOTE_UNAVAILABLE') _invalidateQuote();
        _error = error.status == 503 ? strings.unavailable : strings.error;
      });
    } catch (_) {
      if (mounted) setState(() => _error = strings.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openHistory() => Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => _RideHistory(api: _api, maps: widget.maps),
        ),
      );

  /// The KUNDE Maps map across the top of the screen: empty over Almaty until
  /// both addresses exist, then the pickup, destination and road route.
  Widget _hero() {
    final maps = widget.maps!;
    final pickup = _pickup;
    final destination = _destination;
    if (pickup != null && destination != null) {
      return RideRoutePreviewPanel(
        maps: maps,
        pickup: pickup,
        destination: destination,
        hero: true,
      );
    }
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      child: maps.map(
        context,
        markers: [
          if (pickup != null)
            MapMarker(
              id: 'pickup',
              point: pointOf(pickup),
              color: MapMarker.origin,
            ),
        ],
        height: 300,
      ),
    );
  }

  /// Classes on screen. The map flow shows what the server priced; before the
  /// quotes arrive (or when all failed) the standard three stay visible.
  List<String> _visibleClasses(bool mapMode) {
    if (!mapMode) return _baseClasses;
    if (_quoted && _quotes.isNotEmpty) {
      return [
        for (final value in _allClasses)
          if (_quotes.containsKey(value)) value
      ];
    }
    return _baseClasses;
  }

  /// Pickup and destination. In the map flow the rows read like the reference:
  /// a coloured marker, the chosen address and a chevron or "+".
  Widget _addressCard(RideStrings s, bool mapMode) {
    final scheme = Theme.of(context).colorScheme;
    final pickup = _pickup;
    final destination = _destination;
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: Icon(
              mapMode ? Icons.circle : Icons.trip_origin,
              size: mapMode ? 14 : null,
              color: mapMode ? scheme.primary : null,
            ),
            title: Text(mapMode ? (pickup?.label ?? s.pickup) : s.pickup),
            subtitle: mapMode || pickup == null ? null : Text(pickup.label),
            trailing: mapMode ? const Icon(Icons.chevron_right_rounded) : null,
            onTap: _busy ? null : () => _chooseAddress(true),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(
              Icons.location_on,
              color: mapMode ? Colors.red : null,
            ),
            title: Text(
              mapMode ? (destination?.label ?? s.destination) : s.destination,
            ),
            subtitle:
                mapMode || destination == null ? null : Text(destination.label),
            trailing: mapMode
                ? Icon(
                    destination == null
                        ? Icons.add_rounded
                        : Icons.chevron_right_rounded,
                    color: scheme.primary,
                  )
                : null,
            onTap: _busy ? null : () => _chooseAddress(false),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    final quote = _quote;
    final mapMode = widget.maps != null;
    return Scaffold(
      extendBodyBehindAppBar: mapMode,
      appBar: AppBar(
        backgroundColor: mapMode ? Colors.transparent : null,
        elevation: mapMode ? 0 : null,
        scrolledUnderElevation: mapMode ? 0 : null,
        title: mapMode ? null : Text(s.rides),
        leading: mapMode && Navigator.of(context).canPop()
            ? Padding(
                padding: const EdgeInsets.all(6),
                child: IconButton.filledTonal(
                  tooltip: s.back,
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              )
            : null,
        actions: [
          if (mapMode)
            IconButton.filledTonal(
              tooltip: s.history,
              icon: const Icon(Icons.history_rounded),
              onPressed: _busy ? null : _openHistory,
            )
          else
            IconButton(
              tooltip: s.history,
              icon: const Icon(Icons.history_rounded),
              onPressed: _busy ? null : _openHistory,
            ),
          if (mapMode) const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        top: !mapMode,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: mapMode ? EdgeInsets.zero : const EdgeInsets.all(16),
                children: [
                  if (mapMode) _hero(),
                  Padding(
                    padding:
                        mapMode ? const EdgeInsets.all(16) : EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _addressCard(s, mapMode),
                        const SizedBox(height: 16),
                        Text(
                          s.tariffLabel,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        for (final value in _visibleClasses(mapMode))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: RideTariffCard(
                              value: value,
                              selected: value == _rideClass,
                              price: mapMode
                                  ? _quotes[value] == null
                                      ? null
                                      : rideFare(_quotes[value]!.fare)
                                  : value == _rideClass && quote != null
                                      ? '${quote.fare} KZT'
                                      : null,
                              onTap: _busy
                                  ? null
                                  : () => setState(() {
                                        if (mapMode) {
                                          _select(value);
                                        } else {
                                          _rideClass = value;
                                          _invalidateQuote();
                                        }
                                      }),
                            ),
                          ),
                        if (quote?.synthetic == true)
                          ListTile(
                            leading: const Icon(Icons.science_outlined),
                            title: Text(s.synthetic),
                          ),
                        // The map flow already shows distance and typical time in
                        // the route preview above; the list flow has no map.
                        if (quote != null && !mapMode)
                          Card(
                            child: ListTile(
                              leading: const Icon(Icons.route_outlined),
                              title: Text(
                                s.t(
                                  '${quote.distanceMeters} м · ${(quote.durationSeconds / 60).ceil()} мин',
                                  '${quote.distanceMeters} м · ${(quote.durationSeconds / 60).ceil()} мин',
                                  '${quote.distanceMeters} m · ${(quote.durationSeconds / 60).ceil()} min',
                                ),
                              ),
                            ),
                          ),
                        if (_error != null) _InlineError(message: _error!),
                        if (mapMode && _error != null && _quoted)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: _quoting ? null : _quoteAll,
                              child: Text(s.retry),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_busy || _quoting) const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: mapMode
                        ? FilledButton(
                            onPressed: _busy || _quoting || quote == null
                                ? null
                                : _order,
                            child: Text(
                              quote == null
                                  ? s.order
                                  : '${s.order} · ${rideFare(quote.fare)}',
                            ),
                          )
                        : FilledButton(
                            onPressed:
                                _busy || _pickup == null || _destination == null
                                    ? null
                                    : _submit,
                            child: Text(quote == null ? s.quote : s.confirm),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddressPicker extends StatefulWidget {
  const _AddressPicker({required this.api});
  final RideApi api;

  @override
  State<_AddressPicker> createState() => _AddressPickerState();
}

class _AddressPickerState extends State<_AddressPicker> {
  final _field = TextEditingController();
  Future<List<RideAddress>>? _results;

  void _search() {
    final query = _field.text.trim();
    if (query.length < 2) return;
    setState(() {
      _results = widget.api.search(query, RideStrings(context).language);
    });
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .72,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          children: [
            TextField(
              controller: _field,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              maxLength: 160,
              decoration: InputDecoration(
                labelText: s.search,
                suffixIcon: IconButton(
                  tooltip: s.search,
                  onPressed: _search,
                  icon: const Icon(Icons.search_rounded),
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<RideAddress>>(
                future: _results,
                builder: (context, snapshot) {
                  if (_results == null) return const SizedBox.shrink();
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    final failure = snapshot.error;
                    return _InlineError(
                      message:
                          failure is IdentityApiError && failure.status == 503
                              ? s.unavailable
                              : s.error,
                    );
                  }
                  final addresses = snapshot.data ?? const <RideAddress>[];
                  if (addresses.isEmpty) {
                    return Center(child: Text(s.noAddresses));
                  }
                  return ListView(
                    children: [
                      for (final address in addresses)
                        ListTile(
                          title: Text(address.label),
                          onTap: () => Navigator.of(context).pop(address),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RideHistory extends StatefulWidget {
  const _RideHistory({required this.api, this.maps});
  final RideApi api;
  final KundeMaps? maps;

  @override
  State<_RideHistory> createState() => _RideHistoryState();
}

class _RideHistoryState extends State<_RideHistory> {
  late Future<List<RideTrip>> _history;

  @override
  void initState() {
    super.initState();
    _history = widget.api.history();
  }

  void _reloadHistory() => setState(() {
        _history = widget.api.history();
      });

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.history)),
      body: SafeArea(
        child: FutureBuilder<List<RideTrip>>(
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
                ),
              );
            }
            final trips = snapshot.data ?? const <RideTrip>[];
            if (trips.isEmpty) return Center(child: Text(s.noRides));
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final trip in trips)
                  Card(
                    child: ListTile(
                      title: Text(trip.synthetic
                          ? '${s.synthetic} · ${s.status(trip.status)}'
                          : s.status(trip.status)),
                      subtitle: Text(
                        MaterialLocalizations.of(context)
                            .formatShortDate(trip.createdAt.toLocal()),
                      ),
                      trailing: Text('${trip.fare} KZT'),
                      onTap: () async {
                        await Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => _RideDetails(
                                api: widget.api, trip: trip, maps: widget.maps),
                          ),
                        );
                        if (mounted) {
                          _reloadHistory();
                        }
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RideDetails extends StatefulWidget {
  const _RideDetails({required this.api, required this.trip, this.maps});
  final RideApi api;
  final RideTrip trip;
  final KundeMaps? maps;

  @override
  State<_RideDetails> createState() => _RideDetailsState();
}

class _RideDetailsState extends State<_RideDetails> {
  late RideTrip _trip;
  Timer? _poll;
  bool _pending = false;
  bool _failed = false;
  RideDriverLocation? _driverLocation;

  @override
  void initState() {
    super.initState();
    _trip = widget.trip;
    if (_trip.active) {
      _poll = Timer.periodic(
        const Duration(seconds: 5),
        (_) => unawaited(_refresh()),
      );
      unawaited(_refresh());
    }
  }

  Future<void> _refresh({bool cancel = false}) async {
    if (_pending) return;
    setState(() => _pending = true);
    try {
      final trip = cancel
          ? await widget.api.cancel(_trip.id)
          : _trip.searching
              ? await widget.api.dispatch(_trip.id)
              : await widget.api.detail(_trip.id);
      if (!mounted) return;
      if (!trip.active) _poll?.cancel();
      setState(() {
        _trip = trip;
        _driverLocation = null;
        _failed = false;
      });
      if (trip.active && !trip.searching) {
        try {
          final location = await widget.api.driverLocation(trip.id);
          if (mounted) setState(() => _driverLocation = location);
        } catch (_) {
          // The server can withhold position without interrupting trip status.
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _driverLocation = null;
          _failed = true;
        });
      }
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  Future<void> _confirmCancellation() async {
    final s = RideStrings(context);
    final cancel = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.cancel),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.back),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.cancel),
          ),
        ],
      ),
    );
    if (cancel == true && mounted) await _refresh(cancel: true);
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    if (_trip.searching) {
      return Scaffold(
        backgroundColor: KundePalette.darkBackground,
        appBar: AppBar(
          backgroundColor: KundePalette.darkBackground,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: RideSearchingView(
          requested: _trip.status == 'REQUESTED',
          footer: Column(
            children: [
              if (_failed) _InlineError(message: s.error),
              if (_failed)
                TextButton(
                  onPressed: _pending ? null : _refresh,
                  child: Text(s.retry),
                ),
              if (_trip.cancellable)
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                  ),
                  onPressed: _pending ? null : _confirmCancellation,
                  child: Text(s.cancel),
                ),
            ],
          ),
        ),
      );
    }
    if (_trip.status == 'COMPLETED') {
      return Scaffold(
        appBar: AppBar(title: Text(s.rides)),
        body: SafeArea(
          child: RideCompletedView(
            trip: _trip,
            onDone: () => Navigator.of(context).maybePop(),
            onRate: (stars, comment) =>
                widget.api.rate(_trip.id, stars, comment),
          ),
        ),
      );
    }
    final location = _driverLocation;
    final onMap = widget.maps != null && location != null;
    return Scaffold(
      extendBodyBehindAppBar: onMap,
      appBar: AppBar(
        backgroundColor: onMap ? Colors.transparent : null,
        elevation: onMap ? 0 : null,
        scrolledUnderElevation: onMap ? 0 : null,
        title: onMap ? null : Text(s.rides),
        leading: onMap
            ? Padding(
                padding: const EdgeInsets.all(6),
                child: IconButton.filledTonal(
                  tooltip: s.back,
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              )
            : null,
      ),
      body: SafeArea(
        top: !onMap,
        child: ListView(
          padding: onMap ? EdgeInsets.zero : const EdgeInsets.all(16),
          children: [
            if (onMap)
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(28)),
                child: RideDriverMapPanel(
                  maps: widget.maps!,
                  location: location,
                  height: 320,
                ),
              ),
            Padding(
              padding: onMap ? const EdgeInsets.all(16) : EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_trip.driver == null)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.local_taxi_outlined),
                        title: Semantics(
                          liveRegion: true,
                          child: Text(s.status(_trip.status)),
                        ),
                        subtitle: Text('${_trip.fare} KZT'),
                      ),
                    ),
                  if (_trip.synthetic)
                    ListTile(
                        leading: const Icon(Icons.science_outlined),
                        title: Text(s.synthetic)),
                  if (_trip.driver case final driver?)
                    RideDriverCard(
                        driver: driver, status: s.status(_trip.status)),
                  if (_trip.driver != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(s.fareLabel),
                          Text(
                            '${_trip.fare} KZT',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                  if (_driverLocation case final location?
                      when widget.maps == null)
                    ListTile(
                      leading: const Icon(Icons.my_location),
                      title: Text(s.t('Местоположение водителя',
                          'Жүргізушінің орналасуы', 'Driver location')),
                      subtitle: Text(
                          '${location.latitude.toStringAsFixed(5)}, ${location.longitude.toStringAsFixed(5)}'),
                    ),
                  if (_failed) _InlineError(message: s.error),
                  if (_failed)
                    TextButton(
                      onPressed: _pending ? null : _refresh,
                      child: Text(s.retry),
                    ),
                  if (_trip.cancellable)
                    OutlinedButton(
                      onPressed: _pending ? null : _confirmCancellation,
                      child: Text(s.cancel),
                    ),
                  TextButton.icon(
                    icon: const Icon(Icons.support_agent),
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                          builder: (_) => Scaffold(
                                appBar: AppBar(
                                    title: Text(s.t(
                                        'Поддержка поездки',
                                        'Сапар бойынша қолдау',
                                        'Ride support'))),
                                body: SafeArea(
                                  child: ListView(
                                    padding: const EdgeInsets.all(16),
                                    children: [
                                      SupportPanel(
                                          auth: widget.api.auth,
                                          rideId: _trip.id)
                                    ],
                                  ),
                                ),
                              )),
                    ),
                    label: Text(s.t('Сообщить о проблеме',
                        'Мәселе туралы хабарлау', 'Report a problem')),
                  ),
                  if (_pending) const LinearProgressIndicator(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            message,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      );
}
