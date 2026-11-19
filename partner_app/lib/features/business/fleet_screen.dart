import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../data/partner_api.dart';
import '../../data/partner_operations.dart';
import '../../widgets/states.dart';

class FleetScreen extends StatefulWidget {
  const FleetScreen({
    required this.ops,
    required this.canManage,
    required this.isOwner,
    super.key,
  });

  final PartnerOperations ops;
  final bool canManage;
  final bool isOwner;

  @override
  State<FleetScreen> createState() => _FleetScreenState();
}

class _FleetScreenState extends State<FleetScreen> {
  Map<String, dynamic>? _fleet;
  Object? _failure;
  bool _missing = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
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

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final fleet = _fleet;
    final failure = _failure;
    final stats = fleet?['stats'] as Map<String, dynamic>?;
    final approved = fleet?['status'] == 'APPROVED';
    return Scaffold(
      appBar: AppBar(
        title: Text(s.fleet),
        actions: [
          IconButton(
            onPressed: _busy ? null : _load,
            tooltip: s.refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _busy && fleet == null && !_missing
            ? const SkeletonList(count: 2)
            : failure != null && fleet == null && !_missing
                ? ErrorView(error: failure, onRetry: _load)
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_busy) const LinearProgressIndicator(),
                      if (failure != null)
                        Semantics(
                          liveRegion: true,
                          child: ErrorView(error: failure, onRetry: _load),
                        ),
                      if (_missing) ...[
                        Text(s.fleetMissing),
                        if (widget.isOwner)
                          FilledButton(
                            onPressed: _busy
                                ? null
                                : () => _load(widget.ops.applyFleet),
                            child: Text(s.fleetApply),
                          ),
                      ],
                      if (fleet != null) ...[
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.local_taxi_outlined),
                            title:
                                Text(s.fleetStatus(fleet['status'] as String)),
                            subtitle: stats == null
                                ? null
                                : Text(s.fleetStats(stats['active'] as int,
                                    stats['completed'] as int)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(s.fleetDrivers,
                            style: Theme.of(context).textTheme.titleLarge),
                        for (final driver in _rows('drivers'))
                          Card(
                            child: ListTile(
                              title: Text(driver['name'] as String),
                              subtitle: Text([
                                s.fleetStatus(driver['status'] as String),
                                s.fleetAvailability(driver['online'] == true),
                                if (driver['vehicle'] != null)
                                  driver['vehicle'] as String,
                                if (driver['plate'] != null)
                                  driver['plate'] as String,
                                if (driver['vehicleStatus'] != null)
                                  s.fleetStatus(
                                      driver['vehicleStatus'] as String),
                              ].join(' · ')),
                              trailing: widget.canManage
                                  ? IconButton(
                                      tooltip: s.fleetDetach,
                                      icon: const Icon(
                                          Icons.person_remove_outlined),
                                      onPressed: _busy
                                          ? null
                                          : () => _confirmDetach(
                                              driver['id'] as String),
                                    )
                                  : null,
                            ),
                          ),
                        if (approved && widget.canManage)
                          for (final driver in _rows('candidates'))
                            ListTile(
                              title: Text(driver['name'] as String),
                              trailing: TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _load(() => widget.ops
                                        .assignFleetDriver(
                                            driver['id'] as String, true)),
                                child: Text(s.fleetAssign),
                              ),
                            ),
                        const SizedBox(height: 16),
                        Text(s.fleetTrips,
                            style: Theme.of(context).textTheme.titleLarge),
                        for (final trip in _rows('trips'))
                          ListTile(
                            title:
                                Text(s.fleetStatus(trip['status'] as String)),
                            subtitle: Text([
                              if (trip['synthetic'] == true) s.fleetTest,
                              MaterialLocalizations.of(context).formatShortDate(
                                  DateTime.parse(trip['createdAt'] as String)
                                      .toLocal()),
                            ].join(' · ')),
                          ),
                      ],
                    ],
                  ),
      ),
    );
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
