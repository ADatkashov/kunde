import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../home/data/kunde_api.dart';
import '../identity/auth_repository.dart';
import 'education_labels.dart';

class EducationEnrollmentScreen extends StatefulWidget {
  const EducationEnrollmentScreen({
    required this.api,
    required this.auth,
    required this.courseId,
    super.key,
  });

  final KundeApi api;
  final AuthRepository auth;
  final String courseId;

  @override
  State<EducationEnrollmentScreen> createState() => _EducationEnrollmentState();
}

class _EducationEnrollmentState extends State<EducationEnrollmentScreen> {
  late Future<List<dynamic>> _cohorts =
      widget.api.educationCohorts(widget.courseId);
  final _keys = <(String, int), String>{};
  Map<String, dynamic>? _selected;
  bool _busy = false;
  bool _failed = false;

  Future<void> _confirm() async {
    final selected = _selected;
    if (_busy || selected == null) return;
    final id = selected['id'] as String;
    final price = selected['priceMinor'] as int;
    final random = Random.secure();
    final key = _keys.putIfAbsent(
      (id, price),
      () => List.generate(
              24, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
          .join(),
    );
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final data = await widget.api.educationRequest(
        'enrollments',
        token: await widget.auth.accessToken(),
        method: 'POST',
        key: key,
        body: {
          'cohortId': id,
          'expectedPriceMinor': price,
          'paymentMethod': 'TEST_CARD'
        },
      ) as Map<String, dynamic>;
      if (!mounted) return;
      Navigator.of(context).pushReplacement<void, void>(MaterialPageRoute(
        builder: (_) => _LearningScreen(
            api: widget.api, auth: widget.auth, id: data['id'] as String),
      ));
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: Text(educationLabel(context, 'Формат и поток',
                'Формат және топ', 'Format and cohort'))),
        body: _EducationLoad<List<dynamic>>(
          future: _cohorts,
          onRetry: () => setState(() {
            _selected = null;
            _failed = false;
            _cohorts = widget.api.educationCohorts(widget.courseId);
          }),
          builder: (groups) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (groups.isEmpty)
                Text(educationLabel(context, 'Доступных потоков пока нет',
                    'Қолжетімді топтар әзірге жоқ', 'No available cohorts')),
              for (final raw in groups) _cohort(raw as Map<String, dynamic>),
              if (_selected != null) ...[
                const SizedBox(height: 16),
                Text(educationLabel(
                    context,
                    'Тестовая карта. Реального списания нет.',
                    'Сынақ картасы. Нақты төлем алынбайды.',
                    'Test card. No real charge.')),
                FilledButton(
                  onPressed: _busy ? null : _confirm,
                  child: Text(educationLabel(context, 'Оплатить TEST_CARD',
                      'TEST_CARD арқылы төлеу', 'Pay with TEST_CARD')),
                ),
              ],
              if (_failed)
                Text(educationLabel(
                    context,
                    'Запись не подтверждена. Повторите попытку или обновите список потоков.',
                    'Тіркелу расталмады. Қайталап көріңіз немесе топтарды жаңартыңыз.',
                    'Enrollment was not confirmed. Retry or refresh the cohorts.')),
              if (_failed)
                TextButton(
                  onPressed: () => setState(() {
                    _selected = null;
                    _failed = false;
                    _cohorts = widget.api.educationCohorts(widget.courseId);
                  }),
                  child: Text(educationLabel(context, 'Обновить потоки',
                      'Топтарды жаңарту', 'Refresh cohorts')),
                ),
            ],
          ),
        ),
      );

  Widget _cohort(Map<String, dynamic> group) {
    final remaining = group['remaining'] as int;
    return Card(
      child: ListTile(
        selected: _selected == group,
        enabled: !_busy && remaining > 0,
        leading: Icon(
            _selected == group ? Icons.check_circle : Icons.circle_outlined),
        title: Text(educationFormat(context, group['format'] as String)),
        subtitle: Text([
          _schedule(context, group),
          educationPrice(context, group['priceMinor'] as int),
          educationLabel(context, 'Мест: $remaining', 'Орын: $remaining',
              'Seats: $remaining'),
        ].join('\n')),
        onTap: () => setState(() {
          _selected = group;
          _failed = false;
        }),
      ),
    );
  }
}

String _schedule(BuildContext context, Map<String, dynamic> data) {
  final starts = data['startsAt'] as String?;
  if (starts == null) {
    return educationLabel(
        context, 'В своём темпе', 'Өз қарқыныңызбен', 'Self-paced');
  }
  final localizations = MaterialLocalizations.of(context);
  String format(String value) {
    final date = DateTime.parse(value).toUtc().add(const Duration(hours: 5));
    return '${localizations.formatCompactDate(date)} '
        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(date), alwaysUse24HourFormat: true)}';
  }

  return '${format(starts)} – ${format(data['endsAt'] as String)} (UTC+5)';
}

class EducationMyCourses extends StatefulWidget {
  const EducationMyCourses({required this.api, required this.auth, super.key});

  final KundeApi api;
  final AuthRepository auth;

  @override
  State<EducationMyCourses> createState() => _EducationMyCoursesState();
}

class _EducationMyCoursesState extends State<EducationMyCourses> {
  static const _pageSize = 30;
  int _offset = 0;
  late Future<List<dynamic>> _courses = _load();

  Future<List<dynamic>> _load() async => await widget.api.educationRequest(
        'enrollments?limit=$_pageSize&offset=$_offset',
        token: await widget.auth.accessToken(),
      ) as List<dynamic>;

  void _page(int offset) => setState(() {
        _offset = offset;
        _courses = _load();
      });

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: Text(educationLabel(
                context, 'Мои курсы', 'Курстарым', 'My courses'))),
        body: _EducationLoad<List<dynamic>>(
          future: _courses,
          onRetry: () => _page(_offset),
          builder: (courses) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (courses.isEmpty)
                Text(educationLabel(context, 'Записей пока нет',
                    'Тіркелу әзірге жоқ', 'No enrollments')),
              for (final course in courses)
                ListTile(
                  title: Text(course['title'] as String),
                  subtitle: Text(course['completedAt'] == null
                      ? _schedule(context, course as Map<String, dynamic>)
                      : educationLabel(context, 'Курс завершён',
                          'Курс аяқталды', 'Course completed')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.of(context).push<void>(MaterialPageRoute(
                      builder: (_) => _LearningScreen(
                          api: widget.api,
                          auth: widget.auth,
                          id: course['id'] as String),
                    ));
                    if (mounted) _page(_offset);
                  },
                ),
              Wrap(
                children: [
                  if (_offset > 0)
                    TextButton(
                        onPressed: () => _page(_offset - _pageSize),
                        child: Text(educationLabel(
                            context, 'Назад', 'Артқа', 'Previous'))),
                  if (courses.length == _pageSize)
                    TextButton(
                        onPressed: () => _page(_offset + _pageSize),
                        child: Text(
                            educationLabel(context, 'Ещё', 'Тағы', 'More'))),
                ],
              ),
            ],
          ),
        ),
      );
}

class _LearningScreen extends StatefulWidget {
  const _LearningScreen(
      {required this.api, required this.auth, required this.id});

  final KundeApi api;
  final AuthRepository auth;
  final String id;

  @override
  State<_LearningScreen> createState() => _LearningState();
}

class _LearningState extends State<_LearningScreen> {
  late Future<Map<String, dynamic>> _learning = _load();
  (int, int)? _pending;

  Future<Map<String, dynamic>> _load() async =>
      await widget.api.educationRequest(
        'enrollments/${widget.id}/learning',
        token: await widget.auth.accessToken(),
      ) as Map<String, dynamic>;

  Future<Map<String, dynamic>> _complete(int module, int lesson) async {
    final data = await widget.api.educationRequest(
      'enrollments/${widget.id}/lessons/$module/$lesson/completion',
      method: 'PUT',
      token: await widget.auth.accessToken(),
    ) as Map<String, dynamic>;
    _pending = null;
    return data;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title:
                Text(educationLabel(context, 'Обучение', 'Оқу', 'Learning'))),
        body: _EducationLoad<Map<String, dynamic>>(
          future: _learning,
          onRetry: () => setState(() {
            final pending = _pending;
            _learning =
                pending == null ? _load() : _complete(pending.$1, pending.$2);
          }),
          builder: (data) {
            final enrollment = data['enrollment'] as Map<String, dynamic>;
            final lessons = data['lessons'] as List<dynamic>;
            final complete =
                lessons.where((item) => item['completed'] == true).length;
            final code = enrollment['certificateCode'] as String?;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(enrollment['title'] as String,
                    style: Theme.of(context).textTheme.headlineSmall),
                Text(educationLabel(context, 'Тестовая оплата подтверждена',
                    'Сынақ төлемі расталды', 'Test payment captured')),
                Text(_schedule(context, enrollment)),
                if (lessons.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                      value: complete / lessons.length,
                      semanticsLabel: educationLabel(context, 'Прогресс курса',
                          'Курс барысы', 'Course progress')),
                  Text('$complete / ${lessons.length}'),
                ],
                for (final lesson in lessons)
                  if (lesson['content'] == null)
                    ListTile(
                        leading: const Icon(Icons.lock_outline),
                        title: Text(lesson['title'] as String))
                  else
                    ExpansionTile(
                      title: Text(lesson['title'] as String),
                      leading: Icon(lesson['completed'] == true
                          ? Icons.check_circle
                          : Icons.menu_book_outlined),
                      childrenPadding: const EdgeInsets.all(16),
                      children: [
                        Text(lesson['content'] as String),
                        if (lesson['completed'] != true)
                          FilledButton(
                            onPressed: () => setState(() {
                              final module = lesson['modulePosition'] as int;
                              final position = lesson['lessonPosition'] as int;
                              _pending = (module, position);
                              _learning = _complete(module, position);
                            }),
                            child: Text(educationLabel(
                                context,
                                'Завершить урок',
                                'Сабақты аяқтау',
                                'Complete lesson')),
                          ),
                      ],
                    ),
                if (code != null)
                  ListTile(
                    title: Text(educationLabel(
                        context,
                        'Код проверки завершения курса',
                        'Курсты аяқтауды тексеру коды',
                        'Course completion verification code')),
                    subtitle: SelectableText(code),
                    trailing: IconButton(
                      tooltip: educationLabel(
                          context, 'Копировать', 'Көшіру', 'Copy'),
                      icon: const Icon(Icons.copy),
                      onPressed: () =>
                          Clipboard.setData(ClipboardData(text: code)),
                    ),
                  ),
              ],
            );
          },
        ),
      );
}

class _EducationLoad<T> extends StatelessWidget {
  const _EducationLoad(
      {required this.future, required this.onRetry, required this.builder});

  final Future<T> future;
  final VoidCallback onRetry;
  final Widget Function(T) builder;

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data;
          if (data != null) return builder(data);
          return Center(
              child: TextButton(
            onPressed: onRetry,
            child: Text(educationLabel(
                context,
                'Не удалось загрузить. Повторить',
                'Жүктеу сәтсіз. Қайталау',
                'Could not load. Retry')),
          ));
        },
      );
}
