import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

import '../identity/auth_repository.dart';
import 'ride_api.dart';
import 'ride_strings.dart';

class RidesScreen extends StatefulWidget {
  const RidesScreen({required this.api, super.key});

  final RideApi api;

  @override
  State<RidesScreen> createState() => _RidesScreenState();
}

class _RidesScreenState extends State<RidesScreen> {
  RideAddress? _pickup;
  RideAddress? _destination;
  String _rideClass = 'ECONOMY';
  RideQuote? _quote;
  String? _key;
  bool _busy = false;
  String? _error;

  RideApi get _api => widget.api;

  void _invalidateQuote() {
    _quote = null;
    _key = null;
    _error = null;
  }

  Future<void> _chooseAddress(bool pickup) async {
    final address = await showModalBottomSheet<RideAddress>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AddressPicker(api: _api),
    );
    if (address == null || !mounted) return;
    setState(() {
      if (pickup) {
        _pickup = address;
      } else {
        _destination = address;
      }
      _invalidateQuote();
    });
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
            builder: (_) => _RideDetails(api: _api, trip: trip),
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

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    final quote = _quote;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.rides),
        actions: [
          IconButton(
            tooltip: s.history,
            icon: const Icon(Icons.history_rounded),
            onPressed: _busy
                ? null
                : () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                          builder: (_) => _RideHistory(api: _api)),
                    ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.trip_origin),
                    title: Text(s.pickup),
                    subtitle: _pickup == null ? null : Text(_pickup!.label),
                    onTap: _busy ? null : () => _chooseAddress(true),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.location_on_outlined),
                    title: Text(s.destination),
                    subtitle:
                        _destination == null ? null : Text(_destination!.label),
                    onTap: _busy ? null : () => _chooseAddress(false),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _rideClass,
              decoration: InputDecoration(
                labelText: s.t('Тариф', 'Тариф', 'Fare class'),
              ),
              items: [
                for (final value in ['ECONOMY', 'COMFORT', 'BUSINESS'])
                  DropdownMenuItem(
                    value: value,
                    child: Text(s.rideClass(value)),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (value) => setState(() {
                        _rideClass = value!;
                        _invalidateQuote();
                      }),
            ),
            if (quote?.synthetic == true)
              ListTile(
                leading: const Icon(Icons.science_outlined),
                title: Text(s.synthetic),
              ),
            if (quote != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.route_outlined),
                  title: Text('${quote.fare} KZT'),
                  subtitle: Text(
                    s.t(
                      '${quote.distanceMeters} м · ${(quote.durationSeconds / 60).ceil()} мин',
                      '${quote.distanceMeters} м · ${(quote.durationSeconds / 60).ceil()} мин',
                      '${quote.distanceMeters} m · ${(quote.durationSeconds / 60).ceil()} min',
                    ),
                  ),
                ),
              ),
            if (_error != null) _InlineError(message: _error!),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy || _pickup == null || _destination == null
                  ? null
                  : _submit,
              child: Text(quote == null ? s.quote : s.confirm),
            ),
            if (_busy) const LinearProgressIndicator(),
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
    setState(
      () => _results = widget.api.search(query, RideStrings(context).language),
    );
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
  const _RideHistory({required this.api});
  final RideApi api;

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
                  onPressed: () =>
                      setState(() => _history = widget.api.history()),
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
                            builder: (_) =>
                                _RideDetails(api: widget.api, trip: trip),
                          ),
                        );
                        if (mounted) {
                          setState(() => _history = widget.api.history());
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
  const _RideDetails({required this.api, required this.trip});
  final RideApi api;
  final RideTrip trip;

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
    return Scaffold(
      appBar: AppBar(title: Text(s.rides)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
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
            if (_driverLocation case final location?)
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
            if (_pending) const LinearProgressIndicator(),
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
