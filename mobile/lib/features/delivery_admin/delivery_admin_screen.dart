import 'package:flutter/material.dart';

import '../identity/auth_repository.dart';
import '../rides/ride_strings.dart';

enum DeliveryAdminArea { couriers, shipments, complaints }

class DeliveryAdminScreen extends StatefulWidget {
  const DeliveryAdminScreen(
      {required this.auth, required this.area, super.key});

  final AuthRepository auth;
  final DeliveryAdminArea area;

  @override
  State<DeliveryAdminScreen> createState() => _DeliveryAdminScreenState();
}

class _DeliveryAdminScreenState extends State<DeliveryAdminScreen> {
  static const _root = 'admin/deliveries';
  late Future<List<Map<String, dynamic>>> _rows = _load();
  bool _busy = false;
  bool _failed = false;

  Future<List<Map<String, dynamic>>> _load() async {
    final path = switch (widget.area) {
      DeliveryAdminArea.couriers => '$_root/couriers?includeReviewed=true',
      DeliveryAdminArea.shipments => _root,
      DeliveryAdminArea.complaints => '$_root/complaints',
    };
    return (await widget.auth.authorizedJson('GET', path) as List)
        .cast<Map<String, dynamic>>();
  }

  void _reload() {
    setState(() {
      _rows = _load();
    });
  }

  Future<void> _mutate(String path, {Map<String, dynamic>? body}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await widget.auth.authorizedJson('POST', '$_root/$path', body: body);
      if (mounted) _reload();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    final title = switch (widget.area) {
      DeliveryAdminArea.couriers => s.t('Курьеры', 'Курьерлер', 'Couriers'),
      DeliveryAdminArea.shipments =>
        s.t('Отправления', 'Жөнелтілімдер', 'Shipments'),
      DeliveryAdminArea.complaints =>
        s.t('Жалобы на доставку', 'Жеткізу шағымдары', 'Delivery complaints'),
    };
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: [
        IconButton(
          tooltip: s.retry,
          icon: const Icon(Icons.refresh),
          onPressed: _busy ? null : _reload,
        ),
      ]),
      body: SafeArea(
          child: FutureBuilder(
        future: _rows,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(s.error));
          }
          return ListView(padding: const EdgeInsets.all(16), children: [
            if (_busy) const LinearProgressIndicator(),
            if (_failed) Semantics(liveRegion: true, child: Text(s.error)),
            if (snapshot.data!.isEmpty)
              Text(s.t(
                  'Записей пока нет.', 'Әзірге жазба жоқ.', 'No entries yet.')),
            for (final row in snapshot.data!) _item(row, s),
          ]);
        },
      )),
    );
  }

  Widget _item(Map<String, dynamic> row, RideStrings s) {
    final status = row['status'] as String;
    final id = (row['id'] ?? row['userId']) as String;
    final title = row['name'] as String? ?? id;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          Text(_status(status, s)),
          if (row['vehicle'] case final String vehicle)
            Text(switch (vehicle) {
              'WALK' => s.t('Пешком', 'Жаяу', 'On foot'),
              'BICYCLE' => s.t('Велосипед', 'Велосипед', 'Bicycle'),
              'MOTORCYCLE' => s.t('Мотоцикл', 'Мотоцикл', 'Motorcycle'),
              _ => s.t('Автомобиль', 'Автокөлік', 'Car'),
            }),
          if (row['syntheticRoute'] == true)
            Text(s.t('DEV/TEST · тестовый маршрут', 'DEV/TEST · сынақ бағыты',
                'DEV/TEST · synthetic route')),
          if (row['message'] case final String message) Text(message),
          Wrap(spacing: 8, children: [
            if (widget.area == DeliveryAdminArea.couriers)
              for (final approve in [true, false])
                if (status != (approve ? 'APPROVED' : 'BLOCKED'))
                  TextButton(
                    onPressed:
                        _busy ? null : () => _review(id, approve, row, s),
                    child: Text(approve
                        ? s.t('Допустить', 'Рұқсат беру', 'Approve')
                        : s.t('Заблокировать', 'Бұғаттау', 'Block')),
                  ),
            if (widget.area == DeliveryAdminArea.shipments) ...[
              TextButton(
                  onPressed: () => _audit(id, s),
                  child: Text(s.t('Аудит', 'Аудит', 'Audit trail'))),
              if (status == 'DELIVERY_FAILED')
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _confirm(
                          '$id/return',
                          s.t('Назначить возврат', 'Қайтаруды тағайындау',
                              'Request return'),
                          s),
                  child: Text(s.t('Назначить возврат', 'Қайтаруды тағайындау',
                      'Request return')),
                ),
            ],
            if (widget.area == DeliveryAdminArea.complaints &&
                status != 'RESOLVED')
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _confirm(
                        'complaints/$id/resolve',
                        s.t('Закрыть жалобу', 'Шағымды жабу',
                            'Resolve complaint'),
                        s),
                child: Text(
                    s.t('Закрыть жалобу', 'Шағымды жабу', 'Resolve complaint')),
              ),
          ]),
        ]),
      ),
    );
  }

  Future<void> _confirm(String path, String label, RideStrings s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(title: Text(label), actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.t('Назад', 'Кері', 'Back'))),
        FilledButton(
            onPressed: () => Navigator.pop(context, true), child: Text(label)),
      ]),
    );
    if (mounted && confirmed == true) await _mutate(path);
  }

  Future<void> _review(
      String id, bool approve, Map<String, dynamic> row, RideStrings s) async {
    final limits = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ReviewDialog(approve: approve, profile: row),
    );
    if (mounted && limits != null) {
      await _mutate('couriers/$id/decision',
          body: {'decision': approve ? 'APPROVED' : 'BLOCKED', ...limits});
    }
  }

  Future<void> _audit(String id, RideStrings s) async {
    final events = widget.auth.authorizedJson('GET', '$_root/$id/audit');
    await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(s.t(
                  'Аудит отправления', 'Жөнелтілім аудиті', 'Shipment audit')),
              content: FutureBuilder(
                future: events,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) return Text(s.error);
                  return SingleChildScrollView(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final event in snapshot.data as List<dynamic>)
                        Text(
                            '${_status(event['status'] as String, s)} · ${event['occurredAt']}'),
                    ],
                  ));
                },
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(s.t('Закрыть', 'Жабу', 'Close'))),
              ],
            ));
  }

  String _status(String state, RideStrings s) => switch (state) {
        'PENDING' =>
          s.t('Ожидает проверки', 'Тексеруді күтуде', 'Pending review'),
        'APPROVED' => s.t('Допущен', 'Рұқсат берілді', 'Approved'),
        'BLOCKED' => s.t('Заблокирован', 'Бұғатталды', 'Blocked'),
        'DELIVERY_FAILED' =>
          s.t('Вручение не выполнено', 'Тапсыру орындалмады', 'Handoff failed'),
        'RETURN_REQUESTED' =>
          s.t('Назначен возврат', 'Қайтару тағайындалды', 'Return requested'),
        'RETURNING' => s.t(
            'Возвращается отправителю', 'Жіберушіге қайтарылуда', 'Returning'),
        'RETURNED_TO_SENDER' => s.t('Возвращено', 'Қайтарылды', 'Returned'),
        'OPEN' => s.t('Открыта', 'Ашық', 'Open'),
        'RESOLVED' => s.t('Закрыта', 'Жабық', 'Resolved'),
        _ => state,
      };
}

class _ReviewDialog extends StatefulWidget {
  const _ReviewDialog({required this.approve, required this.profile});
  final bool approve;
  final Map<String, dynamic> profile;

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();
  late final _weight =
      TextEditingController(text: widget.profile['maxGrams']?.toString());
  late final _side =
      TextEditingController(text: widget.profile['maxSideCm']?.toString());

  @override
  void dispose() {
    _reason.dispose();
    _weight.dispose();
    _side.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    final apply = widget.approve
        ? s.t('Допустить', 'Рұқсат беру', 'Approve')
        : s.t('Заблокировать', 'Бұғаттау', 'Block');
    return AlertDialog(
        title: Text(apply),
        content: Form(
          key: _form,
          child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: _reason,
              decoration:
                  InputDecoration(labelText: s.t('Причина', 'Себеп', 'Reason')),
              maxLength: 200,
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? s.error : null,
            ),
            if (widget.approve)
              for (final (controller, label, max) in [
                (
                  _weight,
                  s.t('Макс. вес, г', 'Шекті салмақ, г', 'Max weight, g'),
                  50000
                ),
                (
                  _side,
                  s.t('Макс. сторона, см', 'Шекті өлшем, см', 'Max side, cm'),
                  200
                ),
              ])
                TextFormField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: label),
                  validator: (value) {
                    final number = int.tryParse(value ?? '');
                    return number == null || number < 1 || number > max
                        ? s.error
                        : null;
                  },
                ),
          ])),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(s.t('Назад', 'Кері', 'Back'))),
          FilledButton(
              onPressed: () {
                if (_form.currentState!.validate()) {
                  Navigator.pop(context, <String, dynamic>{
                    'reason': _reason.text.trim(),
                    'maxGrams': int.tryParse(_weight.text) ?? 1,
                    'maxSideCm': int.tryParse(_side.text) ?? 1,
                  });
                }
              },
              child: Text(apply)),
        ]);
  }
}
