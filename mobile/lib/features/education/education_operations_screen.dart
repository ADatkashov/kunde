import 'package:flutter/material.dart';

import '../identity/auth_repository.dart';
import 'education_labels.dart';
import 'education_text_dialog.dart';

class EducationOperationsScreen extends StatefulWidget {
  const EducationOperationsScreen({
    required this.auth,
    this.admin = false,
    super.key,
  });
  final AuthRepository auth;
  final bool admin;

  @override
  State<EducationOperationsScreen> createState() => _EducationOperationsState();
}

class _EducationOperationsState extends State<EducationOperationsScreen> {
  String get _root =>
      widget.admin ? 'admin/education/courses' : 'executor/education/sessions';
  String? _session;
  bool _scheduled = false;
  bool _busy = false;
  late Future<List<Map<String, dynamic>>> _rows = _load();

  Future<List<Map<String, dynamic>>> _load() async {
    final path = _session == null ? _root : '$_root/$_session/roster';
    return (await widget.auth.authorizedJson('GET', path) as List)
        .cast<Map<String, dynamic>>();
  }

  void _reload() {
    final rows = _load();
    setState(() {
      _rows = rows;
    });
  }

  Future<void> _decision(String id, String decision) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => EducationTextDialog(
        title: educationLabel(
          context,
          'Причина решения',
          'Шешімнің себебі',
          'Decision reason',
        ),
        maxLength: 200,
      ),
    );
    if (reason == null || !mounted) return;
    await _save('POST', '$_root/$id/decision', {
      'decision': decision,
      'reason': reason,
    });
  }

  Future<void> _review(String id, bool approved) async {
    final feedback = await showDialog<String>(
      context: context,
      builder: (context) => EducationTextDialog(
        title: educationLabel(
          context,
          'Комментарий к ответу',
          'Жауапқа пікір',
          'Answer feedback',
        ),
        maxLength: 1000,
      ),
    );
    if (!mounted || feedback == null) return;
    await _save('PUT', '$_root/$_session/roster/$id/assignment', {
      'approved': approved,
      'feedback': feedback,
    });
  }

  Future<void> _revokeCertificate() async {
    final code = await showDialog<String>(
      context: context,
      builder: (context) => EducationTextDialog(
        title: educationLabel(
          context,
          'Код сертификата',
          'Сертификат коды',
          'Certificate code',
        ),
        maxLength: 36,
      ),
    );
    if (!mounted || code == null) return;
    if (!RegExp(r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')
        .hasMatch(code)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            educationLabel(
              context,
              'Проверьте код',
              'Кодты тексеріңіз',
              'Check the code',
            ),
          ),
        ),
      );
      return;
    }
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => EducationTextDialog(
        title: educationLabel(
          context,
          'Причина отзыва сертификата',
          'Сертификатты қайтару себебі',
          'Reason for certificate revocation',
        ),
        maxLength: 200,
      ),
    );
    if (!mounted || reason == null) return;
    await _save('PUT', 'admin/education/certificates/$code/revocation', {
      'reason': reason,
    });
  }

  Future<void> _save(
    String method,
    String path,
    Map<String, dynamic> body,
  ) async {
    setState(() => _busy = true);
    try {
      await widget.auth.authorizedJson(method, path, body: body);
      if (mounted) _reload();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              educationLabel(
                context,
                'Изменение не сохранено',
                'Өзгеріс сақталмады',
                'Change was not saved',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(
            widget.admin
                ? educationLabel(
                    context,
                    'Модерация курсов',
                    'Курстарды модерациялау',
                    'Course moderation',
                  )
                : _session == null
                    ? educationLabel(
                        context, 'Мои занятия', 'Сабақтарым', 'My classes')
                    : educationLabel(
                        context, 'Посещаемость', 'Қатысу', 'Attendance'),
          ),
          actions: [
            if (widget.admin)
              IconButton(
                tooltip: educationLabel(
                  context,
                  'Отозвать сертификат',
                  'Сертификатты қайтару',
                  'Revoke certificate',
                ),
                icon: const Icon(Icons.remove_moderator_outlined),
                onPressed: _busy ? null : _revokeCertificate,
              ),
            if (_session != null)
              IconButton(
                tooltip: educationLabel(
                  context,
                  'К занятиям',
                  'Сабақтарға',
                  'Back to classes',
                ),
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
                  child: Text(
                    educationLabel(context, 'Повторить', 'Қайталау', 'Retry'),
                  ),
                ),
              );
            }
            if (data.isEmpty) {
              return Center(
                child: Text(
                  educationLabel(
                      context, 'Список пуст', 'Тізім бос', 'No items'),
                ),
              );
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
            Text(
              row['title'] as String? ?? id,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (widget.admin) ...[
              Text('${row['organization']} · $status'),
              Text(row['description'] as String? ?? ''),
              Wrap(
                spacing: 8,
                children: [
                  if (status == 'PENDING_REVIEW') ...[
                    FilledButton(
                      onPressed: _busy ? null : () => _decision(id, 'PUBLISH'),
                      child: Text(
                        educationLabel(
                          context,
                          'Опубликовать',
                          'Жариялау',
                          'Publish',
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _busy ? null : () => _decision(id, 'REJECT'),
                      child: Text(
                        educationLabel(
                          context,
                          'Отклонить',
                          'Қабылдамау',
                          'Reject',
                        ),
                      ),
                    ),
                  ],
                  if (status == 'PUBLISHED')
                    TextButton(
                      onPressed: _busy ? null : () => _decision(id, 'SUSPEND'),
                      child: Text(
                        educationLabel(context, 'Скрыть', 'Жасыру', 'Suspend'),
                      ),
                    ),
                ],
              ),
            ] else if (_session == null) ...[
              if (starts != null) Text('$starts — ${row['endsAt']}'),
              Semantics(
                identifier: 'education-roster-$id',
                child: OutlinedButton(
                  onPressed: () {
                    _session = id;
                    _scheduled = row['format'] != 'ONLINE_RECORDED';
                    _reload();
                  },
                  child: Text(educationLabel(
                      context, 'Открыть список', 'Тізімді ашу', 'Open roster')),
                ),
              ),
            ] else ...[
              if (_scheduled)
                Wrap(
                  spacing: 8,
                  children: [
                    for (final (code, label) in [
                      (
                        'PRESENT',
                        educationLabel(
                          context,
                          'Присутствовал',
                          'Қатысты',
                          'Present',
                        ),
                      ),
                      (
                        'ABSENT',
                        educationLabel(
                          context,
                          'Отсутствовал',
                          'Қатыспады',
                          'Absent',
                        ),
                      ),
                    ])
                      Semantics(
                        identifier:
                            'education-attendance-${code.toLowerCase()}-$id',
                        child: ChoiceChip(
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
                      ),
                  ],
                ),
              if (row['response'] case final String response) Text(response),
              if (row['feedback'] case final String feedback) Text(feedback),
              if (row['assignmentStatus'] == 'SUBMITTED')
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton(
                      onPressed: _busy ? null : () => _review(id, true),
                      child: Text(
                        educationLabel(
                          context,
                          'Принять',
                          'Қабылдау',
                          'Approve',
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _busy ? null : () => _review(id, false),
                      child: Text(
                        educationLabel(
                          context,
                          'На доработку',
                          'Қайта орындау',
                          'Return',
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }
}
