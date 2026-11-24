import 'dart:async';

import 'package:flutter/material.dart';

import 'package:kunde_auth/auth_repository.dart';
import 'package:kunde_ui/ride_strings.dart';

/// A driver as the admin sees it: profile plus the one registered vehicle.
class DriverAccessRow {
  DriverAccessRow(Map<String, dynamic> json)
      : id = json['userId'] as String,
        name = json['displayName'] as String,
        status = json['status'] as String,
        online = json['online'] == true,
        vehicle = json['vehicle'] as Map<String, dynamic>?;

  final String id;
  final String name;
  final String status;
  final bool online;
  final Map<String, dynamic>? vehicle;

  String? get vehicleStatus => vehicle?['status'] as String?;

  bool get blocked => status == 'BLOCKED' || vehicleStatus == 'BLOCKED';

  /// Cleared for the line: the profile and the vehicle are both approved.
  bool get cleared => status == 'APPROVED' && vehicleStatus == 'APPROVED';

  bool get pending => !blocked && !cleared;
}

enum _Filter { pending, cleared, blocked }

/// One screen for the only decision that matters before a driver can go online:
/// approve the driver and the vehicle together, or block the driver.
class RideDriverAccessScreen extends StatefulWidget {
  const RideDriverAccessScreen({required this.auth, super.key});

  final AuthRepository auth;

  @override
  State<RideDriverAccessScreen> createState() => _RideDriverAccessScreenState();
}

class _RideDriverAccessScreenState extends State<RideDriverAccessScreen> {
  late Future<List<DriverAccessRow>> _rows = _load();
  _Filter _filter = _Filter.pending;
  bool _busy = false;
  bool _failed = false;

  Future<List<DriverAccessRow>> _load() async {
    final ids = (await widget.auth.authorizedJson(
            'GET', 'admin/rides/drivers?includeReviewed=true') as List<dynamic>)
        .cast<String>();
    final rows = await Future.wait(ids.map((id) async => DriverAccessRow(
        await widget.auth.authorizedJson('GET', 'admin/rides/drivers/$id')
            as Map<String, dynamic>)));
    return rows;
  }

  void _reload() {
    final rows = _load();
    setState(() {
      _rows = rows;
    });
  }

  Future<void> _decide(DriverAccessRow row, String decision) async {
    final s = RideStrings(context);
    final approve = decision == 'APPROVED';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(approve
            ? s.t('Допустить на линию?', 'Желіге жіберу керек пе?',
                'Allow on the line?')
            : s.t('Заблокировать водителя?', 'Жүргізушіні бұғаттау керек пе?',
                'Block the driver?')),
        content: Text(
            '${row.name}${row.vehicle == null ? '' : ' · ${row.vehicle!['description']} · ${row.vehicle!['plate']}'}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.back)),
          FilledButton(
            key: const Key('driver-access-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(approve
                ? s.t('Допустить', 'Жіберу', 'Allow')
                : s.t('Заблокировать', 'Бұғаттау', 'Block')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      Future<void> post(Map<String, dynamic> body) => widget.auth
          .authorizedJson('POST', 'admin/rides/drivers/${row.id}/decision',
              body: body, expected: {200, 204});
      if (row.status != decision) await post({'decision': decision});
      // A block stops the driver on its own; an approval needs the vehicle too.
      if (approve && row.vehicle != null && row.vehicleStatus != decision) {
        await post({'decision': decision, 'vehicleId': row.vehicle!['id']});
      }
      if (mounted) _reload();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
      if (mounted) _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _statusLabel(RideStrings s, String? status) => switch (status) {
        'APPROVED' => s.t('Одобрено', 'Мақұлданды', 'Approved'),
        'BLOCKED' => s.t('Заблокировано', 'Бұғатталды', 'Blocked'),
        null => s.t('Нет авто', 'Көлік жоқ', 'No vehicle'),
        _ => s.t('На проверке', 'Тексеруде', 'Pending'),
      };

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('Допуск на линию', 'Желіге жіберу', 'Line access')),
        actions: [
          IconButton(
              onPressed: _busy ? null : _reload,
              tooltip: s.retry,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: FutureBuilder<List<DriverAccessRow>>(
        future: _rows,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            final error = snapshot.error;
            return Center(
                child: Text(error is IdentityApiError && error.status == 403
                    ? s.t('Доступ запрещён', 'Рұқсат жоқ', 'Access denied')
                    : s.error));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snapshot.data!;
          final shown = all
              .where((r) => switch (_filter) {
                    _Filter.pending => r.pending,
                    _Filter.cleared => r.cleared,
                    _Filter.blocked => r.blocked,
                  })
              .toList();
          int count(bool Function(DriverAccessRow) test) =>
              all.where(test).length;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (_failed) Semantics(liveRegion: true, child: Text(s.error)),
              Wrap(spacing: 8, children: [
                for (final (filter, label, n) in [
                  (
                    _Filter.pending,
                    s.t('Ждут допуска', 'Рұқсат күтуде', 'Waiting'),
                    count((r) => r.pending)
                  ),
                  (
                    _Filter.cleared,
                    s.t('Допущены', 'Жіберілді', 'Allowed'),
                    count((r) => r.cleared)
                  ),
                  (
                    _Filter.blocked,
                    s.t('Заблокированы', 'Бұғатталды', 'Blocked'),
                    count((r) => r.blocked)
                  ),
                ])
                  ChoiceChip(
                    key: Key('driver-filter-${filter.name}'),
                    label: Text('$label · $n'),
                    selected: _filter == filter,
                    onSelected: (_) => setState(() => _filter = filter),
                  ),
              ]),
              const SizedBox(height: 8),
              if (shown.isEmpty)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child:
                        Text(s.t('Нет записей', 'Жазбалар жоқ', 'No records'))),
              for (final row in shown) _card(s, row),
            ],
          );
        },
      ),
    );
  }

  Widget _card(RideStrings s, DriverAccessRow row) {
    final vehicle = row.vehicle;
    return Card(
      key: Key('driver-${row.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                  child: Text(row.name,
                      style: Theme.of(context).textTheme.titleMedium)),
              if (row.online)
                Chip(label: Text(s.t('На линии', 'Желіде', 'Online'))),
            ]),
            const SizedBox(height: 4),
            Text(vehicle == null
                ? s.t('Автомобиль не добавлен', 'Көлік қосылмаған',
                    'No vehicle added')
                : '${vehicle['description']} · ${vehicle['plate']} · ${s.rideClass(vehicle['rideClass'] as String)}'),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              Chip(
                  label: Text(
                      '${s.t('Водитель', 'Жүргізуші', 'Driver')}: ${_statusLabel(s, row.status)}')),
              Chip(
                  label: Text(
                      '${s.t('Авто', 'Көлік', 'Vehicle')}: ${_statusLabel(s, row.vehicleStatus)}')),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              if (!row.cleared)
                FilledButton(
                  key: Key('driver-allow-${row.id}'),
                  onPressed: _busy || vehicle == null
                      ? null
                      : () => _decide(row, 'APPROVED'),
                  child: Text(s.t('Допустить на линию', 'Желіге жіберу',
                      'Allow on the line')),
                ),
              if (row.status != 'BLOCKED')
                OutlinedButton(
                  key: Key('driver-block-${row.id}'),
                  onPressed: _busy ? null : () => _decide(row, 'BLOCKED'),
                  child: Text(s.t('Заблокировать', 'Бұғаттау', 'Block')),
                ),
            ]),
          ],
        ),
      ),
    );
  }
}
