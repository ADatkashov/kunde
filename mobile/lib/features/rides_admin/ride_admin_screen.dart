import 'package:flutter/material.dart';

import '../delivery_admin/delivery_admin_screen.dart';
import '../identity/auth_repository.dart';
import '../rides/ride_strings.dart';

class RideAdminScreen extends StatelessWidget {
  const RideAdminScreen({required this.auth, super.key});

  final AuthRepository auth;

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('KUNDE Rides Admin'),
        actions: [
          IconButton(
            onPressed: auth.logout,
            tooltip: s.t('Выйти', 'Шығу', 'Sign out'),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final (area, label, icon) in [
            (
              DeliveryAdminArea.couriers,
              s.t('Курьеры', 'Курьерлер', 'Couriers'),
              Icons.inventory_2_outlined
            ),
            (
              DeliveryAdminArea.shipments,
              s.t('Отправления', 'Жөнелтілімдер', 'Shipments'),
              Icons.local_shipping_outlined
            ),
            (
              DeliveryAdminArea.complaints,
              s.t('Жалобы на доставку', 'Жеткізу шағымдары',
                  'Delivery complaints'),
              Icons.flag_outlined
            ),
          ])
            Card(
                child: ListTile(
              leading: Icon(icon),
              title: Text(label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push<void>(MaterialPageRoute(
                builder: (_) => DeliveryAdminScreen(auth: auth, area: area),
              )),
            )),
          for (final (route, label, icon) in [
            (
              'drivers',
              s.t('Водители', 'Жүргізушілер', 'Drivers'),
              Icons.person_outline
            ),
            (
              'fleets',
              s.t('Автопарки', 'Автопарктер', 'Fleets'),
              Icons.local_taxi_outlined
            ),
            ('trips', s.rides, Icons.route_outlined),
            (
              'complaints',
              s.t('Жалобы', 'Шағымдар', 'Complaints'),
              Icons.flag_outlined
            ),
          ])
            Card(
              child: ListTile(
                leading: Icon(icon),
                title: Text(label),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                      builder: (_) =>
                          _AdminQueue(auth: auth, route: route, label: label)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AdminQueue extends StatefulWidget {
  const _AdminQueue(
      {required this.auth, required this.route, required this.label});

  final AuthRepository auth;
  final String route;
  final String label;

  @override
  State<_AdminQueue> createState() => _AdminQueueState();
}

class _AdminQueueState extends State<_AdminQueue> {
  late Future<List<dynamic>> _rows = _loadQueue();
  bool _busy = false;
  Object? _failure;

  Future<List<dynamic>> _loadQueue() => _getList(widget.route == 'drivers'
      ? 'drivers?includeReviewed=true'
      : widget.route);

  Future<List<dynamic>> _getList(String path) async =>
      await widget.auth.authorizedJson('GET', 'admin/rides/$path')
          as List<dynamic>;

  void _reloadQueue() => setState(() {
        _rows = _loadQueue();
      });

  Future<void> _mutate(String path, {Map<String, dynamic>? body}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await widget.auth.authorizedJson('POST', 'admin/rides/$path',
          body: body, expected: {200, 204});
      if (mounted) _reloadQueue();
    } catch (error) {
      if (mounted) setState(() => _failure = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resolve(String id) async {
    final s = RideStrings(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.t(
            'Закрыть жалобу?', 'Шағымды жабу керек пе?', 'Resolve complaint?')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.back)),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.t('Закрыть', 'Жабу', 'Resolve')),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await _mutate('complaints/$id/resolve');
    }
  }

  Future<void> _review(String id, {String? vehicleId}) async {
    final s = RideStrings(context);
    final decision = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.t(
            'Решение модерации', 'Модерация шешімі', 'Moderation decision')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: Text(s.back)),
          TextButton(
            onPressed: () => Navigator.pop(context, 'BLOCKED'),
            child: Text(s.t('Заблокировать', 'Бұғаттау', 'Block')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'APPROVED'),
            child: Text(s.t('Одобрить', 'Мақұлдау', 'Approve')),
          ),
        ],
      ),
    );
    if (decision == null || !mounted) return;
    await _mutate('${widget.route}/$id/decision', body: {
      'decision': decision,
      if (vehicleId != null) 'vehicleId': vehicleId
    });
  }

  Future<void> _audit(String id) async {
    final s = RideStrings(context);
    final events = _getList('${widget.route}/$id/audit');
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.t('Журнал действий', 'Әрекеттер журналы', 'Audit log')),
        content: SizedBox(
          width: 480,
          child: FutureBuilder<List<dynamic>>(
            future: events,
            builder: (context, snapshot) {
              if (snapshot.hasError) return Text(s.error);
              if (!snapshot.hasData) return const LinearProgressIndicator();
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final event
                        in snapshot.data!.cast<Map<String, dynamic>>())
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                            '${event['action'] ?? event['status']} · ${event['occurredAt']}'),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: Text(s.back))
        ],
      ),
    );
  }

  Future<void> _driver(String id) async {
    final s = RideStrings(context);
    final detail = widget.auth.authorizedJson('GET', 'admin/rides/drivers/$id');
    final vehicle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
            s.t('Профиль водителя', 'Жүргізуші профилі', 'Driver profile')),
        content: FutureBuilder<dynamic>(
          future: detail,
          builder: (context, snapshot) {
            if (snapshot.hasError) return Text(s.error);
            if (!snapshot.hasData) return const LinearProgressIndicator();
            final driver = snapshot.data as Map<String, dynamic>;
            final car = driver['vehicle'] as Map<String, dynamic>?;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${driver['displayName']} · ${driver['status']}'),
                if (car != null)
                  Text(
                      '${car['description']} · ${car['plate']} · ${car['status']}'),
                if (car != null)
                  TextButton(
                    onPressed: () =>
                        Navigator.pop(context, car['id'] as String),
                    child: Text(s.t('Проверить автомобиль', 'Көлікті тексеру',
                        'Review vehicle')),
                  ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, ''),
                  child: Text(s.t('Проверить водителя', 'Жүргізушіні тексеру',
                      'Review driver')),
                ),
              ],
            );
          },
        ),
      ),
    );
    if (vehicle != null && mounted) {
      await _review(id, vehicleId: vehicle.isEmpty ? null : vehicle);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.label),
        actions: [
          IconButton(
            onPressed: _busy ? null : _reloadQueue,
            tooltip: s.retry,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<dynamic>>(
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
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (_failure != null)
                Semantics(liveRegion: true, child: Text(s.error)),
              if (snapshot.data!.isEmpty)
                Text(s.t('Нет записей', 'Жазбалар жоқ', 'No records')),
              for (final row in snapshot.data!) _record(s, row),
            ],
          );
        },
      ),
    );
  }

  Widget _record(RideStrings s, Object? raw) {
    final row = raw is Map<String, dynamic> ? raw : {'id': raw};
    final id = row['id'] as String;
    final status = row['status'] as String?;
    return Card(
      child: ListTile(
        title: Text(row['name'] as String? ?? row['message'] as String? ?? id),
        subtitle: status == null
            ? null
            : Text(widget.route == 'trips'
                ? [if (row['synthetic'] == true) s.synthetic, s.status(status)]
                    .join(' · ')
                : status),
        trailing: widget.route == 'trips'
            ? null
            : PopupMenuButton<int>(
                enabled: !_busy,
                onSelected: (action) {
                  if (action == 0) {
                    _audit(id);
                  } else if (widget.route == 'drivers') {
                    _driver(id);
                  } else if (widget.route == 'fleets') {
                    _review(id);
                  } else {
                    _resolve(id);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                      value: 0, child: Text(s.t('Аудит', 'Аудит', 'Audit'))),
                  if (status != 'RESOLVED')
                    PopupMenuItem(
                      value: 1,
                      child: Text(widget.route == 'complaints'
                          ? s.t('Закрыть жалобу', 'Шағымды жабу',
                              'Resolve complaint')
                          : s.t('Рассмотреть', 'Қарау', 'Review')),
                    ),
                ],
              ),
      ),
    );
  }
}
