import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../home/data/kunde_api.dart';
import '../identity/auth_repository.dart';
import 'education_labels.dart';
import 'education_text_dialog.dart';

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
  Future<Map<String, dynamic>> Function()? _pending;
  bool _sharing = false;

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
    return data;
  }

  void _change(Future<Map<String, dynamic>> Function() action) {
    setState(() {
      _pending = action;
      _learning = action().then((updated) {
        _pending = null;
        return updated;
      });
    });
  }

  static String _quizRequestId() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex =
        bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  void _answer(int choice) {
    final request = _quizRequestId();
    _change(() async => await widget.api.educationRequest(
          'enrollments/${widget.id}/quiz-attempts',
          method: 'POST',
          token: await widget.auth.accessToken(),
          body: {'requestId': request, 'choice': choice},
        ) as Map<String, dynamic>);
  }

  Future<void> _shareCertificate() async {
    setState(() => _sharing = true);
    try {
      final bytes = await widget.api
          .educationCertificatePdf(widget.id, await widget.auth.accessToken());
      if (!mounted) return;
      final renderBox = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(bytes, mimeType: 'application/pdf')],
        fileNameOverrides: const ['KUNDE-certificate.pdf'],
        sharePositionOrigin: renderBox == null
            ? null
            : renderBox.localToGlobal(Offset.zero) & renderBox.size,
      ));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
          educationLabel(
              context, 'PDF недоступен', 'PDF қолжетімсіз', 'PDF unavailable'),
        )));
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _submitAssignment() async {
    final response = await showDialog<String>(
      context: context,
      builder: (context) => EducationTextDialog(
        title: educationLabel(context, 'Ответ на задание', 'Тапсырмаға жауап',
            'Assignment response'),
        maxLength: 5000,
      ),
    );
    if (!mounted || response == null) return;
    _change(() async => await widget.api.educationRequest(
          'enrollments/${widget.id}/assignment',
          method: 'PUT',
          token: await widget.auth.accessToken(),
          body: {'response': response},
        ) as Map<String, dynamic>);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title:
                Text(educationLabel(context, 'Обучение', 'Оқу', 'Learning'))),
        body: _EducationLoad<Map<String, dynamic>>(
          future: _learning,
          onRetry: () => _change(_pending ?? _load),
          builder: (data) {
            final enrollment = data['enrollment'] as Map<String, dynamic>;
            final lessons = data['lessons'] as List<dynamic>;
            final complete =
                lessons.where((item) => item['completed'] == true).length;
            final code = enrollment['certificateCode'] as String?;
            final revoked = enrollment['certificateStatus'] == 'REVOKED';
            final quiz = data['quiz'] as Map<String, dynamic>?;
            final assignment = data['assignment'] as Map<String, dynamic>?;
            final quizPassed = quiz?['passed'] == true || code != null;
            final approved =
                assignment?['status'] == 'APPROVED' || code != null;
            final total = lessons.length +
                (quiz == null ? 0 : 1) +
                (assignment == null ? 0 : 1);
            final done = complete +
                (quiz != null && quizPassed ? 1 : 0) +
                (assignment != null && approved ? 1 : 0);
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
                      value: done / total,
                      semanticsLabel: educationLabel(context, 'Прогресс курса',
                          'Курс барысы', 'Course progress')),
                  Text('$done / $total'),
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
                            onPressed: () => _change(() => _complete(
                                  lesson['modulePosition'] as int,
                                  lesson['lessonPosition'] as int,
                                )),
                            child: Text(educationLabel(
                                context,
                                'Завершить урок',
                                'Сабақты аяқтау',
                                'Complete lesson')),
                          ),
                      ],
                    ),
                if (quiz != null && !quizPassed && complete == lessons.length)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(quiz['question'] as String,
                              style: Theme.of(context).textTheme.titleMedium),
                          Text(educationLabel(
                              context,
                              'Попыток осталось: ${quiz['remainingAttempts']}',
                              'Қалған әрекеттер: ${quiz['remainingAttempts']}',
                              'Attempts left: ${quiz['remainingAttempts']}')),
                          for (final (index, option)
                              in (quiz['choices'] as List<dynamic>).indexed)
                            OutlinedButton(
                              onPressed: quiz['remainingAttempts'] == 0
                                  ? null
                                  : () => _answer(index),
                              child: Text(option as String),
                            ),
                        ],
                      ),
                    ),
                  ),
                if (assignment != null && complete == lessons.length)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(assignment['prompt'] as String,
                              style: Theme.of(context).textTheme.titleMedium),
                          if (assignment['response'] case final String response)
                            Text(response),
                          if (assignment['feedback'] case final String feedback)
                            Text(feedback),
                          if (approved)
                            Text(educationLabel(context, 'Задание принято',
                                'Тапсырма қабылданды', 'Assignment approved'))
                          else if (assignment['status'] == 'SUBMITTED')
                            Text(educationLabel(context, 'На проверке',
                                'Тексеруде', 'Under review'))
                          else
                            FilledButton(
                              onPressed: _submitAssignment,
                              child: Text(educationLabel(
                                  context,
                                  'Отправить ответ',
                                  'Жауап жіберу',
                                  'Submit response')),
                            ),
                        ],
                      ),
                    ),
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
                if (code != null && revoked)
                  Text(educationLabel(context, 'Подтверждение отозвано',
                      'Растама қайтарылды', 'Certificate revoked')),
                if (code != null && !revoked)
                  OutlinedButton.icon(
                    onPressed: _sharing ? null : _shareCertificate,
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: Text(educationLabel(
                        context,
                        'Сохранить или отправить PDF',
                        'PDF сақтау немесе жіберу',
                        'Save or share PDF')),
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

/// Existing enrollments remain reachable from Profile while intake is paused.
class ExistingEducationCoursesTile extends StatefulWidget {
  const ExistingEducationCoursesTile(
      {required this.api, required this.auth, super.key});
  final KundeApi api;
  final AuthRepository auth;

  @override
  State<ExistingEducationCoursesTile> createState() =>
      _ExistingEducationCoursesTileState();
}

class _ExistingEducationCoursesTileState
    extends State<ExistingEducationCoursesTile> {
  late final Future<bool> _hasCourses = _check();

  Future<bool> _check() async {
    final courses = await widget.auth
        .authorizedJson('GET', 'education/enrollments?limit=1') as List;
    return courses.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
        future: _hasCourses,
        builder: (context, snapshot) {
          if (snapshot.data != true) return const SizedBox.shrink();
          return Card(
              child: ListTile(
            leading: const Icon(Icons.school_outlined),
            title: Text(educationLabel(
                context, 'Мои курсы', 'Курстарым', 'My courses')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push<void>(MaterialPageRoute(
              builder: (_) =>
                  EducationMyCourses(api: widget.api, auth: widget.auth),
            )),
          ));
        },
      );
}
