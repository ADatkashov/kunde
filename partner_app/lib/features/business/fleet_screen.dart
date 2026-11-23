import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../data/partner_api.dart';
import '../../data/partner_operations.dart';
import '../../widgets/states.dart';

/// KUNDE Taxi for a partner: service overview, fleet and drivers. Every figure
/// comes from the fleet endpoint; revenue, tariffs, zones and analytics are
/// listed as coming soon because the backend has no contract for them yet.
class FleetScreen extends StatefulWidget {
  const FleetScreen({
    required this.ops,
    required this.canManage,
    required this.isOwner,
    this.now = DateTime.now,
    super.key,
  });

  final PartnerOperations ops;
  final bool canManage;
  final bool isOwner;

  /// Clock used to count today's trips; tests pass a fixed one.
  final DateTime Function() now;

  @override
  State<FleetScreen> createState() => _FleetScreenState();
}

class _FleetScreenState extends State<FleetScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  Map<String, dynamic>? _fleet;
  Object? _failure;
  bool _missing = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load([Future<Map<String, dynamic>> Function()? action]) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final data = await (action ?? widget.ops.fleet)();
      if (mounted) {
        setState(() {
          _fleet = data;
          _missing = false;
        });
      }
    } on PartnerApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _missing = error.code == 'RIDE_FLEET_NOT_FOUND' && action == null;
        if (!_missing) _failure = error;
      });
    } catch (error) {
      if (mounted) setState(() => _failure = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Map<String, dynamic>> _rows(String key) =>
      (_fleet?[key] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();

  int _tripsToday() {
    final now = widget.now();
    return _rows('trips').where((trip) {
      final at = DateTime.parse(trip['createdAt'] as String).toLocal();
      return at.year == now.year && at.month == now.month && at.day == now.day;
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final fleet = _fleet;
    final failure = _failure;
    final loading = _busy && fleet == null && !_missing;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.taxiTitle),
        actions: [
          IconButton(
            onPressed: _busy ? null : _load,
            tooltip: s.refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: s.taxiTabService),
            Tab(text: s.fleet),
            Tab(text: s.taxiTabDrivers),
          ],
        ),
      ),
      body: SafeArea(
        child: loading
            ? const SkeletonList(count: 2)
            : failure != null && fleet == null && !_missing
                ? ErrorView(error: failure, onRetry: _load)
                : _missing
                    ? ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          Text(s.fleetMissing),
                          if (widget.isOwner)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: FilledButton(
                                onPressed: _busy
                                    ? null
                                    : () => _load(widget.ops.applyFleet),
                                child: Text(s.fleetApply),
                              ),
                            ),
                        ],
                      )
                    : TabBarView(
                        controller: _tabs,
                        children: [
                          _page([..._service(s)]),
                          _page([..._vehicles(s)]),
                          _page([..._drivers(s)]),
                        ],
                      ),
      ),
    );
  }

  Widget _page(List<Widget> children) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_failure != null)
            Semantics(
              liveRegion: true,
              child: ErrorView(error: _failure!, onRetry: _load),
            ),
          ...children,
        ],
      );

  Iterable<Widget> _service(S s) sync* {
    final fleet = _fleet;
    if (fleet == null) return;
    final stats = fleet['stats'] as Map<String, dynamic>?;
    final scheme = Theme.of(context).colorScheme;
    yield Card(
      color: scheme.primaryContainer,
      child: ListTile(
        leading: Icon(Icons.local_taxi_rounded,
            size: 36, color: scheme.onPrimaryContainer),
        title: Text(
          s.taxiTitle,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: scheme.onPrimaryContainer,
              ),
        ),
        subtitle: Text(
          '${s.taxiSubtitle} · ${s.fleetStatus(fleet['status'] as String)}',
          style: TextStyle(color: scheme.onPrimaryContainer),
        ),
      ),
    );
    yield const SizedBox(height: 12);
    yield Row(
      children: [
        Expanded(
            child: _Kpi(label: s.taxiTripsToday, value: '${_tripsToday()}')),
        const SizedBox(width: 8),
        Expanded(
          child: _Kpi(
            label: s.taxiCompleted,
            value: '${stats?['completed'] ?? 0}',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _Kpi(label: s.taxiActive, value: '${stats?['active'] ?? 0}'),
        ),
      ],
    );
    yield const SizedBox(height: 12);
    yield _MenuTile(
      icon: Icons.directions_car_outlined,
      label: s.taxiMenuFleet,
      onTap: () => _tabs.animateTo(1),
    );
    yield _MenuTile(
      icon: Icons.badge_outlined,
      label: s.taxiMenuDrivers,
      onTap: () => _tabs.animateTo(2),
    );
    yield _MenuTile(
      icon: Icons.receipt_long_outlined,
      label: s.taxiMenuOrders,
    );
    yield _MenuTile(
      icon: Icons.route_outlined,
      label: s.taxiMenuTariffs,
      soon: s.taxiSoon,
    );
    yield _MenuTile(
      icon: Icons.insights_outlined,
      label: s.taxiMenuAnalytics,
      soon: s.taxiSoon,
    );
    yield const SizedBox(height: 16);
    yield Text(s.fleetTrips, style: Theme.of(context).textTheme.titleLarge);
    final trips = _rows('trips');
    if (trips.isEmpty) yield ListTile(title: Text(s.taxiNoTrips));
    for (final trip in trips) {
      yield ListTile(
        title: Text(s.fleetStatus(trip['status'] as String)),
        subtitle: Text([
          if (trip['synthetic'] == true) s.fleetTest,
          MaterialLocalizations.of(context).formatShortDate(
              DateTime.parse(trip['createdAt'] as String).toLocal()),
        ].join(' · ')),
      );
    }
  }

  Iterable<Widget> _vehicles(S s) sync* {
    yield Text(s.taxiVehicles, style: Theme.of(context).textTheme.titleLarge);
    final withVehicle =
        _rows('drivers').where((driver) => driver['vehicle'] != null);
    if (withVehicle.isEmpty) yield ListTile(title: Text(s.taxiNoVehicles));
    for (final driver in withVehicle) {
      yield Card(
        child: ListTile(
          leading: const Icon(Icons.directions_car_filled_rounded),
          title: Text(driver['vehicle'] as String),
          subtitle: Text([
            if (driver['plate'] != null) driver['plate'] as String,
            if (s.taxiClass(driver['rideClass'] as String?).isNotEmpty)
              s.taxiClass(driver['rideClass'] as String?),
            if (driver['vehicleStatus'] != null)
              s.fleetStatus(driver['vehicleStatus'] as String),
          ].join(' · ')),
        ),
      );
    }
  }

  Iterable<Widget> _drivers(S s) sync* {
    final approved = _fleet?['status'] == 'APPROVED';
    yield Text(s.fleetDrivers, style: Theme.of(context).textTheme.titleLarge);
    final drivers = _rows('drivers');
    if (drivers.isEmpty) yield ListTile(title: Text(s.taxiNoDrivers));
    for (final driver in drivers) {
      yield Card(
        child: ListTile(
          title: Text(driver['name'] as String),
          subtitle: Text([
            s.fleetStatus(driver['status'] as String),
            s.fleetAvailability(driver['online'] == true),
            if (driver['vehicle'] != null) driver['vehicle'] as String,
            if (driver['plate'] != null) driver['plate'] as String,
          ].join(' · ')),
          trailing: widget.canManage
              ? IconButton(
                  tooltip: s.fleetDetach,
                  icon: const Icon(Icons.person_remove_outlined),
                  onPressed: _busy
                      ? null
                      : () => _confirmDetach(driver['id'] as String),
                )
              : null,
        ),
      );
    }
    if (approved && widget.canManage) {
      final candidates = _rows('candidates');
      if (candidates.isNotEmpty) {
        yield const SizedBox(height: 16);
        yield Text(s.taxiCandidates,
            style: Theme.of(context).textTheme.titleMedium);
      }
      for (final driver in candidates) {
        yield ListTile(
          title: Text(driver['name'] as String),
          trailing: TextButton(
            onPressed: _busy
                ? null
                : () => _load(() =>
                    widget.ops.assignFleetDriver(driver['id'] as String, true)),
            child: Text(s.fleetAssign),
          ),
        );
      }
    }
  }

  Future<void> _confirmDetach(String driver) async {
    final s = S.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.fleetDetach),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(s.confirm),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _load(() => widget.ops.assignFleetDriver(driver, false));
    }
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(
              value,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.label,
    this.onTap,
    this.soon,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final String? soon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = soon != null;
    return Card(
      child: ListTile(
        enabled: !muted,
        leading: Icon(icon, color: muted ? scheme.outline : scheme.primary),
        title: Text(label),
        trailing: muted
            ? Chip(
                label: Text(soon!),
                visualDensity: VisualDensity.compact,
              )
            : onTap == null
                ? null
                : const Icon(Icons.chevron_right_rounded),
        onTap: muted ? null : onTap,
      ),
    );
  }
}
