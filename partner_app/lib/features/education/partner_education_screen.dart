import 'package:flutter/material.dart';

import '../../data/partner_operations.dart';

String _t(BuildContext context, String ru, String kk, String en) =>
    switch (Localizations.localeOf(context).languageCode) {
      'ru' => ru,
      'kk' => kk,
      _ => en,
    };

class PartnerEducationScreen extends StatefulWidget {
  const PartnerEducationScreen(
      {required this.ops, required this.canManage, super.key});
  final PartnerOperations ops;
  final bool canManage;

  @override
  State<PartnerEducationScreen> createState() => _PartnerEducationState();
}

class _PartnerEducationState extends State<PartnerEducationScreen> {
  String get _root => 'partner/partners/${widget.ops.partnerId}/education';
  late Future<List<Map<String, dynamic>>> _courses = _load();
  bool _busy = false;

  Future<List<Map<String, dynamic>>> _load() =>
      widget.ops.api.getList('$_root/courses');

  void _reload() => setState(() => _courses = _load());

  Future<void> _submit(String path, Map<String, dynamic> payload) async {
    setState(() => _busy = true);
    try {
      await widget.ops.api.postMap(path, payload);
      if (mounted) {
        _reload();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
          _t(context, 'Сохранено', 'Сақталды', 'Saved'),
        )));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
          _t(context, 'Не удалось сохранить изменение',
              'Өзгерісті сақтау сәтсіз', 'Could not save change'),
        )));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _newCourse() async {
    final draft = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _CourseForm(),
    );
    if (draft != null && mounted) await _submit('$_root/courses', draft);
  }

  Future<void> _newCohort(Map<String, dynamic> course) async {
    final form = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _CohortForm(
        format: course['format'] as String,
        instructors: () => widget.ops.api.getList('$_root/instructors'),
      ),
    );
    if (form != null && mounted) {
      await _submit('$_root/courses/${course['id']}/cohorts', form);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: Text(_t(context, 'Управление курсами', 'Курстарды басқару',
                'Manage courses'))),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _courses,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = snapshot.data;
            if (data == null) {
              return Center(
                  child: TextButton(
                onPressed: _reload,
                child: Text(_t(context, 'Повторить', 'Қайталау', 'Retry')),
              ));
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (widget.canManage)
                  FilledButton.icon(
                      onPressed: _busy ? null : _newCourse,
                      icon: const Icon(Icons.add),
                      label: Text(_t(
                          context,
                          'Создать синтетический курс',
                          'Синтетикалық курс құру',
                          'Create synthetic course'))),
                for (final course in data)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(course['title'] as String,
                              style: Theme.of(context).textTheme.titleMedium),
                          Text(course['status'] as String),
                          if (widget.canManage)
                            Wrap(
                              spacing: 8,
                              children: [
                                if (course['status'] == 'DRAFT' ||
                                    course['status'] == 'REJECTED')
                                  TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _submit(
                                            '$_root/courses/${course['id']}/submit',
                                            {}),
                                    child: Text(_t(context, 'На модерацию',
                                        'Модерацияға', 'Submit for review')),
                                  ),
                                if (const {
                                  'DRAFT',
                                  'PENDING_REVIEW',
                                  'PUBLISHED'
                                }.contains(course['status']))
                                  TextButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _newCohort(course),
                                      child: Text(_t(context, 'Создать поток',
                                          'Топ құру', 'Create cohort'))),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      );
}

class _CourseForm extends StatefulWidget {
  const _CourseForm();
  @override
  State<_CourseForm> createState() => _CourseFormState();
}

class _CourseFormState extends State<_CourseForm> {
  final _form = GlobalKey<FormState>();
  final _fields = <String, String>{};
  String _format = 'ONLINE_RECORDED';

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(_t(context, 'Новый курс', 'Жаңа курс', 'New course')),
        content: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _field('title', _t(context, 'Название', 'Атауы', 'Title'), 180),
                _field('description',
                    _t(context, 'Описание', 'Сипаттама', 'Description'), 5000),
                _field(
                    'category',
                    _t(context, 'Код категории', 'Санат коды', 'Category code'),
                    48),
                _field('city', _t(context, 'Город', 'Қала', 'City'), 100),
                _field('language',
                    _t(context, 'Код языка', 'Тіл коды', 'Language code'), 8),
                _field(
                    'priceMinor',
                    _t(context, 'Цена в тиынах', 'Бағасы тиынмен',
                        'Price in tiyn'),
                    14,
                    number: true),
                _field(
                    'durationMinutes',
                    _t(context, 'Длительность (мин)', 'Ұзақтығы (мин)',
                        'Duration (min)'),
                    5,
                    number: true),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _format,
                  decoration: InputDecoration(
                      labelText: _t(context, 'Формат', 'Формат', 'Format')),
                  items: [
                    DropdownMenuItem(
                        value: 'ONLINE_RECORDED',
                        child:
                            Text(_t(context, 'В записи', 'Жазба', 'Recorded'))),
                    DropdownMenuItem(
                        value: 'ONLINE_LIVE',
                        child: Text(
                            _t(context, 'Онлайн', 'Онлайн', 'Live online'))),
                    DropdownMenuItem(
                        value: 'OFFLINE_GROUP',
                        child: Text(_t(context, 'Очная группа', 'Офлайн топ',
                            'In-person group'))),
                  ],
                  onChanged: (value) => setState(() => _format = value!),
                ),
                if (_format == 'ONLINE_RECORDED') ...[
                  _field(
                      'recordedText',
                      _t(context, 'Текст урока', 'Сабақ мәтіні', 'Lesson text'),
                      12000),
                  _field(
                      'assignmentPrompt',
                      _t(
                          context,
                          'Текст задания (необязательно)',
                          'Тапсырма мәтіні (міндетті емес)',
                          'Assignment prompt (optional)'),
                      1500,
                      optional: true),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel)),
          FilledButton(
            onPressed: () {
              if (!_form.currentState!.validate()) return;
              _form.currentState!.save();
              Navigator.pop(context, {
                ..._fields,
                'format': _format,
                'priceMinor': int.parse(_fields['priceMinor']!),
                'durationMinutes': int.parse(_fields['durationMinutes']!),
              });
            },
            child: Text(MaterialLocalizations.of(context).saveButtonLabel),
          ),
        ],
      );

  Widget _field(String key, String label, int max,
          {bool number = false, bool optional = false}) =>
      TextFormField(
        decoration: InputDecoration(labelText: label, counterText: ''),
        keyboardType: number ? TextInputType.number : TextInputType.text,
        maxLength: max,
        onSaved: (value) => _fields[key] = value!.trim(),
        validator: (value) {
          final input = value?.trim() ?? '';
          final parsed = int.tryParse(input);
          if (!optional && input.isEmpty ||
              number &&
                  (parsed == null || parsed < (key == 'priceMinor' ? 0 : 1))) {
            return _t(context, 'Проверьте значение', 'Мәнді тексеріңіз',
                'Check this value');
          }
          return null;
        },
      );
}

class _CohortForm extends StatefulWidget {
  const _CohortForm({required this.format, required this.instructors});
  final String format;
  final Future<List<Map<String, dynamic>>> Function() instructors;

  @override
  State<_CohortForm> createState() => _CohortFormState();
}

class _CohortFormState extends State<_CohortForm> {
  late final Future<List<Map<String, dynamic>>> _teachers =
      widget.instructors();
  String? _instructor;
  DateTime? _start;
  DateTime? _end;
  int? _capacity;
  bool get _recorded => widget.format == 'ONLINE_RECORDED';

  Future<DateTime?> _chooseTime() async {
    final now = DateTime.now().toUtc().add(const Duration(hours: 5));
    final first = DateTime(now.year, now.month, now.day);
    final date = await showDatePicker(
        context: context,
        initialDate: first,
        firstDate: first,
        lastDate: first.add(const Duration(days: 365)));
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
        context: context, initialTime: const TimeOfDay(hour: 19, minute: 0));
    if (time == null) return null;
    return DateTime.utc(date.year, date.month, date.day, time.hour, time.minute)
        .subtract(const Duration(hours: 5));
  }

  String _display(DateTime? date, String label) {
    if (date == null) return label;
    final almaty = date.add(const Duration(hours: 5));
    final locales = MaterialLocalizations.of(context);
    return '$label: ${locales.formatCompactDate(almaty)} ${locales.formatTimeOfDay(TimeOfDay.fromDateTime(almaty))}';
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(_t(context, 'Новый поток', 'Жаңа топ', 'New cohort')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                      labelText: _t(
                          context, 'Количество мест', 'Орын саны', 'Capacity')),
                  onChanged: (value) =>
                      setState(() => _capacity = int.tryParse(value))),
              if (!_recorded) ...[
                Text('Asia/Almaty',
                    style: Theme.of(context).textTheme.bodySmall),
                TextButton(
                  onPressed: () async {
                    final value = await _chooseTime();
                    if (value != null && mounted) {
                      setState(() => _start = value);
                    }
                  },
                  child: Text(_display(
                      _start, _t(context, 'Начало', 'Басталуы', 'Start'))),
                ),
                TextButton(
                  onPressed: () async {
                    final value = await _chooseTime();
                    if (value != null && mounted) setState(() => _end = value);
                  },
                  child: Text(_display(
                      _end, _t(context, 'Окончание', 'Аяқталуы', 'End'))),
                ),
              ],
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _teachers,
                builder: (context, snap) => DropdownButtonFormField<String>(
                  isExpanded: true,
                  decoration: InputDecoration(
                      labelText: _t(
                          context, 'Преподаватель', 'Оқытушы', 'Instructor')),
                  items: [
                    for (final item
                        in snap.data ?? const <Map<String, dynamic>>[])
                      DropdownMenuItem(
                          value: item['id'] as String,
                          child: Text(item['name'] as String))
                  ],
                  onChanged: (value) => setState(() => _instructor = value),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel)),
          FilledButton(
            onPressed: (_capacity ?? 0) < 1 ||
                    (_capacity ?? 0) > 1000 ||
                    (!_recorded &&
                        (_start == null ||
                            _end == null ||
                            !_end!.isAfter(_start!) ||
                            _instructor == null))
                ? null
                : () => Navigator.pop(context, {
                      'format': widget.format,
                      'capacity': _capacity,
                      if (_start != null) 'startsAt': _start!.toIso8601String(),
                      if (_end != null) 'endsAt': _end!.toIso8601String(),
                      if (_instructor != null) 'instructorId': _instructor,
                    }),
            child: Text(MaterialLocalizations.of(context).saveButtonLabel),
          ),
        ],
      );
}
