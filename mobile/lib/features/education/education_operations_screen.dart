import 'package:flutter/material.dart';

import '../identity/auth_repository.dart';
import 'education_labels.dart';

class EducationOperationsScreen extends StatefulWidget {
  const EducationOperationsScreen(
      {required this.auth, this.admin = false, super.key});
  final AuthRepository auth;
  final bool admin;

  @override
  State<EducationOperationsScreen> createState() => _EducationOperationsState();
}

class _EducationOperationsState extends State<EducationOperationsScreen> {
  String get _root =>
      widget.admin ? 'admin/education/courses' : 'executor/education/sessions';
  String? _session;
  bool _busy = false;
  late Future<List<Map<String, dynamic>>> _rows = _load();

  Future<List<Map<String, dynamic>>> _load() async {
    final path = _session == null ? _root : '$_root/$_session/roster';
    return (await widget.auth.authorizedJson('GET', path) as List)
        .cast<Map<String, dynamic>>();
  }

  void _reload() => setState(() => _rows = _load());

  Future<void> _decision(String id, String decision) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => const _ReasonDialog(),
    );
    if (reason == null || !mounted) return;
    await _save('POST', '$_root/$id/decision',
        {'decision': decision, 'reason': reason});
  }

  Future<void> _save(
      String method, String path, Map<String, dynamic> body) async {
    setState(() => _busy = true);
    try {
      await widget.auth.authorizedJson(method, path, body: body);
      if (mounted) _reload();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
          educationLabel(context, 'Изменение не сохранено',
              'Өзгеріс сақталмады', 'Change was not saved'),
        )));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.admin
              ? educationLabel(context, 'Модерация курсов',
                  'Курстарды модерациялау', 'Course moderation')
              : _session == null
                  ? educationLabel(
                      context, 'Мои занятия', 'Сабақтарым', 'My classes')
                  : educationLabel(
                      context, 'Посещаемость', 'Қатысу', 'Attendance')),
          actions: [
            if (_session != null)
              IconButton(
                tooltip: educationLabel(
                    context, 'К занятиям', 'Сабақтарға', 'Back to classes'),
                icon: const Icon(Icons.calendar_month_outlined),
                onPressed: _busy
                    ? null
                    : () {
                        _session = null;
                        _reload();
                      },
              ),
          ],
        ),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _rows,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = snapshot.data;
            if (data == null) {
              return Center(
                  child: TextButton(
                      onPressed: _reload,
                      child: Text(educationLabel(
                          context, 'Повторить', 'Қайталау', 'Retry'))));
            }
            if (data.isEmpty) {
              return Center(
                  child: Text(educationLabel(
                      context, 'Список пуст', 'Тізім бос', 'No items')));
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [for (final row in data) _row(row)],
            );
          },
        ),
      );

  Widget _row(Map<String, dynamic> row) {
    final id = row['id'] as String;
    final status = row['status'];
    final starts = row['startsAt'] as String?;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(row['title'] as String? ?? id,
                style: Theme.of(context).textTheme.titleMedium),
            if (widget.admin) ...[
              Text('${row['organization']} · $status'),
              Text(row['description'] as String? ?? ''),
              Wrap(
                spacing: 8,
                children: [
                  if (status == 'PENDING_REVIEW') ...[
                    FilledButton(
                        onPressed:
                            _busy ? null : () => _decision(id, 'PUBLISH'),
                        child: Text(educationLabel(
                            context, 'Опубликовать', 'Жариялау', 'Publish'))),
                    TextButton(
                        onPressed: _busy ? null : () => _decision(id, 'REJECT'),
                        child: Text(educationLabel(
                            context, 'Отклонить', 'Қабылдамау', 'Reject'))),
                  ],
                  if (status == 'PUBLISHED')
                    TextButton(
                        onPressed:
                            _busy ? null : () => _decision(id, 'SUSPEND'),
                        child: Text(educationLabel(
                            context, 'Скрыть', 'Жасыру', 'Suspend'))),
                ],
              ),
            ] else if (_session == null) ...[
              if (starts != null) Text('$starts — ${row['endsAt']}'),
              OutlinedButton(
                onPressed: () {
                  _session = id;
                  _reload();
                },
                child: Text(educationLabel(
                    context, 'Открыть список', 'Тізімді ашу', 'Open roster')),
              ),
            ] else
              Wrap(
                spacing: 8,
                children: [
                  for (final (code, label) in [
                    (
                      'PRESENT',
                      educationLabel(
                          context, 'Присутствовал', 'Қатысты', 'Present')
                    ),
                    (
                      'ABSENT',
                      educationLabel(
                          context, 'Отсутствовал', 'Қатыспады', 'Absent')
                    ),
                  ])
                    ChoiceChip(
                      label: Text(label),
                      selected: row['attendance'] == code,
                      onSelected: _busy
                          ? null
                          : (_) => _save(
                                'PUT',
                                '$_root/$_session/roster/$id',
                                {'status': code},
                              ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog();

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  String _reason = '';

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(educationLabel(
            context, 'Причина решения', 'Шешімнің себебі', 'Decision reason')),
        content: TextField(
            maxLength: 200,
            autofocus: true,
            onChanged: (value) => setState(() => _reason = value.trim())),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel)),
          FilledButton(
              onPressed: _reason.isEmpty
                  ? null
                  : () => Navigator.pop(context, _reason),
              child: Text(MaterialLocalizations.of(context).okButtonLabel)),
        ],
      );
}
