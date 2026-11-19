import 'package:flutter/material.dart';

import '../auto/data/auto_models.dart' show formatTenge;
import '../identity/auth_repository.dart';
import '../rides/ride_strings.dart';

enum AutoAdminArea {
  specialists,
  venues,
  categories,
  bookings,
  jobs,
  complaints
}

/// KUNDE Auto administration. Every action goes through `/api/v1/admin/auto/**`, which checks the AUTO_OPERATIONS grant on the server;
/// the screen only presents what the server returns (no customer contact data is ever shown).
class AutoAdminScreen extends StatefulWidget {
  const AutoAdminScreen({required this.auth, required this.area, super.key});

  final AuthRepository auth;
  final AutoAdminArea area;

  @override
  State<AutoAdminScreen> createState() => _AutoAdminScreenState();
}

class _AutoAdminScreenState extends State<AutoAdminScreen> {
  static const _root = 'admin/auto';
  late Future<List<Map<String, dynamic>>> _rows = _load();
  List<Map<String, dynamic>> _mobileCategories = [];
  bool _busy = false;
  bool _failed = false;

  Future<List<Map<String, dynamic>>> _load() async {
    final path = switch (widget.area) {
      AutoAdminArea.specialists => '$_root/specialists?includeReviewed=true',
      AutoAdminArea.venues => '$_root/venues',
      AutoAdminArea.categories => '$_root/categories',
      AutoAdminArea.bookings => '$_root/bookings',
      AutoAdminArea.jobs => '$_root/jobs',
      AutoAdminArea.complaints => '$_root/complaints?includeResolved=true',
    };
    if (widget.area == AutoAdminArea.specialists) {
      final cats =
          (await widget.auth.authorizedJson('GET', '$_root/categories') as List)
              .cast<Map<String, dynamic>>();
      _mobileCategories = cats
          .where((c) => c['mobile'] == true && c['enabled'] == true)
          .toList();
    }
    return (await widget.auth.authorizedJson('GET', path) as List)
        .cast<Map<String, dynamic>>();
  }

  void _reload() {
    setState(() {
      _rows = _load();
    });
  }

  Future<void> _mutate(
      String method, String path, Map<String, dynamic> body) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await widget.auth.authorizedJson(method, '$_root/$path', body: body);
      if (mounted) _reload();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _title(RideStrings s) => switch (widget.area) {
        AutoAdminArea.specialists =>
          s.t('Авто-специалисты', 'Авто мамандар', 'Auto specialists'),
        AutoAdminArea.venues =>
          s.t('СТО и автомойки', 'СТО және көлік жуу', 'Stations and washes'),
        AutoAdminArea.categories =>
          s.t('Категории Auto', 'Auto санаттары', 'Auto categories'),
        AutoAdminArea.bookings =>
          s.t('Записи Auto', 'Auto жазылулары', 'Auto bookings'),
        AutoAdminArea.jobs =>
          s.t('Выездные заявки', 'Шығу өтінімдері', 'On-site jobs'),
        AutoAdminArea.complaints =>
          s.t('Жалобы Auto', 'Auto шағымдары', 'Auto complaints'),
      };

  String _status(RideStrings s, String status) => switch (status) {
        'PENDING' => s.t('На проверке', 'Тексерілуде', 'Under review'),
        'APPROVED' => s.t('Одобрен', 'Мақұлданды', 'Approved'),
        'BLOCKED' => s.t('Заблокирован', 'Бұғатталды', 'Blocked'),
        'OPEN' => s.t('Открыта', 'Ашық', 'Open'),
        'RESOLVED' => s.t('Решена', 'Шешілді', 'Resolved'),
        'CONFIRMED' => s.t('Подтверждена', 'Расталды', 'Confirmed'),
        'COMPLETED' => s.t('Завершена', 'Аяқталды', 'Completed'),
        'CANCELLED' => s.t('Отменена', 'Бас тартылды', 'Cancelled'),
        _ => status,
      };

  Future<String?> _ask(String title, String label) => showDialog<String>(
      context: context,
      builder: (_) => _ReasonDialog(title: title, label: label));

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    return Scaffold(
      appBar: AppBar(title: Text(_title(s)), actions: [
        IconButton(
            tooltip: s.retry,
            icon: const Icon(Icons.refresh),
            onPressed: _busy ? null : _reload),
      ]),
      body: SafeArea(
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _rows,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(s.error),
                TextButton(onPressed: _reload, child: Text(s.retry)),
              ]));
            }
            final rows = snap.data!;
            return ListView(padding: const EdgeInsets.all(16), children: [
              if (_busy) const LinearProgressIndicator(),
              if (_failed) Semantics(liveRegion: true, child: Text(s.error)),
              if (rows.isEmpty)
                Text(s.t('Записей пока нет.', 'Әзірге жазба жоқ.',
                    'No entries yet.')),
              for (final row in rows) _item(row, s),
            ]);
          },
        ),
      ),
    );
  }

  Widget _item(Map<String, dynamic> row, RideStrings s) {
    final theme = Theme.of(context);
    switch (widget.area) {
      case AutoAdminArea.categories:
        return Card(
          child: SwitchListTile(
            title: Text(row['nameRu'] as String),
            subtitle: Text(row['mobile'] == true
                ? s.t('Выездная категория', 'Шығу санаты', 'On-site category')
                : s.t('Стационарная', 'Стационарлық', 'Stationary')),
            value: row['enabled'] == true,
            onChanged: _busy
                ? null
                : (v) => _mutate(
                    'PATCH', 'categories/${row['code']}', {'enabled': v}),
          ),
        );
      case AutoAdminArea.venues:
        return Card(
          child: SwitchListTile(
            title: Text(row['name'] as String),
            subtitle: Text(row['open'] == true
                ? s.t('Принимает записи', 'Жазылу қабылдайды',
                    'Accepting bookings')
                : s.t('Заблокировано / закрыто', 'Бұғатталған / жабық',
                    'Blocked / closed')),
            value: row['open'] == true,
            onChanged: _busy
                ? null
                : (v) => _mutate('PATCH', 'venues/${row['id']}', {'open': v}),
          ),
        );
      case AutoAdminArea.specialists:
        final id = row['userId'] as String;
        final status = row['status'] as String;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(row['name'] as String, style: theme.textTheme.titleMedium),
              Text(_status(s, status)),
              if ((row['categories'] as List).isNotEmpty)
                Text((row['categories'] as List).join(', ')),
              Wrap(spacing: 8, children: [
                if (status != 'APPROVED')
                  FilledButton(
                    onPressed: _busy ? null : () => _approve(id, s),
                    child: Text(s.t('Одобрить', 'Мақұлдау', 'Approve')),
                  ),
                if (status != 'BLOCKED')
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            final reason = await _ask(
                                s.t('Заблокировать специалиста',
                                    'Маманды бұғаттау', 'Block specialist'),
                                s.t('Причина', 'Себебі', 'Reason'));
                            if (reason != null) {
                              await _mutate('POST', 'specialists/$id/decision',
                                  {'approve': false, 'reason': reason});
                            }
                          },
                    child: Text(s.t('Заблокировать', 'Бұғаттау', 'Block')),
                  ),
              ]),
            ]),
          ),
        );
      case AutoAdminArea.bookings:
        return Card(
          child: ListTile(
            title: Text('${row['serviceName']} · ${row['venueName']}'),
            subtitle: Text(
                '${_status(s, row['status'] as String)} · ${formatTenge(row['priceMinor'] as int)}'),
          ),
        );
      case AutoAdminArea.jobs:
        return Card(
          child: ListTile(
            title: Text('${row['category']} · ${row['specialist'] ?? '—'}'),
            subtitle: Text(
                '${_status(s, row['status'] as String)} · ${formatTenge(row['priceMinor'] as int)}'),
          ),
        );
      case AutoAdminArea.complaints:
        final open = row['status'] == 'OPEN';
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${row['kind']} · ${_status(s, row['status'] as String)}',
                  style: theme.textTheme.titleMedium),
              Text(row['description'] as String),
              if (row['resolution'] case final String resolution)
                Text(resolution),
              if (open)
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          final text = await _ask(
                              s.t('Решение по жалобе', 'Шағым бойынша шешім',
                                  'Resolution'),
                              s.t('Что сделано', 'Не істелді',
                                  'What was done'));
                          if (text != null) {
                            await _mutate(
                                'POST',
                                'complaints/${row['id']}/resolve',
                                {'resolution': text});
                          }
                        },
                  child: Text(s.t('Закрыть жалобу', 'Шағымды жабу', 'Resolve')),
                ),
            ]),
          ),
        );
    }
  }

  Future<void> _approve(String id, RideStrings s) async {
    final result = await showDialog<_Approval>(
        context: context,
        builder: (_) =>
            _ApprovalDialog(strings: s, categories: _mobileCategories));
    if (result != null) {
      await _mutate('POST', 'specialists/$id/decision', {
        'approve': true,
        'categories': result.categories,
        'reason': result.reason
      });
    }
  }
}

class _Approval {
  const _Approval(this.categories, this.reason);
  final List<String> categories;
  final String reason;
}

/// Owns its controller so it is disposed only after the dialog route has closed.
class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.title, required this.label});
  final String title;
  final String label;
  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    final text = _controller.text.trim();
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 200,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(labelText: widget.label),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.t('Отмена', 'Бас тарту', 'Cancel'))),
        FilledButton(
            onPressed: text.isEmpty ? null : () => Navigator.pop(context, text),
            child: Text(s.t('Подтвердить', 'Растау', 'Confirm'))),
      ],
    );
  }
}

class _ApprovalDialog extends StatefulWidget {
  const _ApprovalDialog({required this.strings, required this.categories});
  final RideStrings strings;
  final List<Map<String, dynamic>> categories;
  @override
  State<_ApprovalDialog> createState() => _ApprovalDialogState();
}

class _ApprovalDialogState extends State<_ApprovalDialog> {
  final _reason = TextEditingController();
  final _selected = <String>{};

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final valid = _selected.isNotEmpty && _reason.text.trim().isNotEmpty;
    return AlertDialog(
      title: Text(
          s.t('Допуск специалиста', 'Маманға рұқсат', 'Specialist approval')),
      content: SingleChildScrollView(
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.t('Виды работ', 'Жұмыс түрлері', 'Kinds of work')),
              for (final c in widget.categories)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(c['nameRu'] as String),
                  value: _selected.contains(c['code']),
                  onChanged: (v) => setState(() {
                    v == true
                        ? _selected.add(c['code'] as String)
                        : _selected.remove(c['code'] as String);
                  }),
                ),
              TextField(
                controller: _reason,
                maxLength: 200,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                    labelText: s.t(
                        'Основание (документы проверены)',
                        'Негіз (құжаттар тексерілді)',
                        'Basis (documents checked)')),
              ),
            ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.t('Отмена', 'Бас тарту', 'Cancel'))),
        FilledButton(
            onPressed: valid
                ? () => Navigator.pop(
                    context, _Approval(_selected.toList(), _reason.text.trim()))
                : null,
            child: Text(s.t('Одобрить', 'Мақұлдау', 'Approve'))),
      ],
    );
  }
}
