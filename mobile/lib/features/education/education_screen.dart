import 'package:flutter/material.dart';

import '../home/data/kunde_api.dart';

String _label(BuildContext context, String ru, String kk, String en) {
  return switch (Localizations.localeOf(context).languageCode) {
    'ru' => ru,
    'kk' => kk,
    _ => en,
  };
}

String _format(BuildContext context, String code) => switch (code) {
  'ONLINE_RECORDED' => _label(context, 'В записи', 'Жазба', 'Recorded'),
  'ONLINE_LIVE' => _label(
    context,
    'Онлайн с преподавателем',
    'Оқытушымен онлайн',
    'Live online',
  ),
  'OFFLINE_GROUP' => _label(
    context,
    'Очно в группе',
    'Топпен офлайн',
    'In-person group',
  ),
  'OFFLINE_INDIVIDUAL' => _label(
    context,
    'Очно индивидуально',
    'Жеке офлайн',
    'In-person one-to-one',
  ),
  'HYBRID' => _label(context, 'Смешанный', 'Аралас', 'Hybrid'),
  _ => _label(context, 'Все форматы', 'Барлық формат', 'All formats'),
};

String _price(BuildContext context, int minor) {
  final whole = MaterialLocalizations.of(context).formatDecimal(minor ~/ 100);
  final fraction = minor % 100;
  if (fraction == 0) return '$whole ₸';
  final separator = Localizations.localeOf(context).languageCode == 'en'
      ? '.'
      : ',';
  return '$whole$separator${fraction.toString().padLeft(2, '0')} ₸';
}

class EducationScreen extends StatefulWidget {
  const EducationScreen({required this.api, super.key});

  final KundeApi api;

  @override
  State<EducationScreen> createState() => _EducationScreenState();
}

class _EducationScreenState extends State<EducationScreen> {
  final _search = TextEditingController();
  String _query = '';
  String _formatCode = '';
  int _offset = 0;
  late Future<Map<String, dynamic>> _result = _load();

  Future<Map<String, dynamic>> _load() => widget.api.loadEducationCourses(
    query: _query,
    format: _formatCode,
    offset: _offset,
  );

  void _searchCourses(String text) => setState(() {
    _query = text.trim();
    _offset = 0;
    _result = _load();
  });

  void _page(int offset) => setState(() {
    _offset = offset;
    _result = _load();
  });

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = _label(
      context,
      'Образование и курсы',
      'Білім және курстар',
      'Education & Courses',
    );
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: FutureBuilder(
        future: _result,
        builder: (context, snapshot) {
          final items = snapshot.data?['items'] as List<dynamic>? ?? const [];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2C1159), Color(0xFF6720B3)],
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.school_rounded,
                        color: Color(0xFFE9D5FF),
                        size: 36,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _search,
                maxLength: 120,
                buildCounter: (
                  _, {
                  required currentLength,
                  required isFocused,
                  maxLength,
                }) => null,
                textInputAction: TextInputAction.search,
                onSubmitted: _searchCourses,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: _label(
                    context,
                    'Курс или школа',
                    'Курс немесе мектеп',
                    'Course or school',
                  ),
                  suffixIcon: IconButton(
                    tooltip: MaterialLocalizations.of(context).searchFieldLabel,
                    icon: const Icon(Icons.search),
                    onPressed: () => _searchCourses(_search.text),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _formatCode,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: _label(context, 'Формат', 'Формат', 'Format'),
                ),
                items: [
                  for (final code in const [
                    '',
                    'ONLINE_RECORDED',
                    'ONLINE_LIVE',
                    'OFFLINE_GROUP',
                    'OFFLINE_INDIVIDUAL',
                    'HYBRID',
                  ])
                    DropdownMenuItem(
                      value: code,
                      child: Text(_format(context, code)),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _formatCode = value;
                    _offset = 0;
                    _result = _load();
                  });
                },
              ),
              const SizedBox(height: 16),
              if (snapshot.connectionState != ConnectionState.done)
                const Center(child: CircularProgressIndicator())
              else if (snapshot.hasError)
                _Retry(onRetry: () => _page(_offset))
              else ...[
                if (items.isEmpty)
                  Text(
                    _label(
                      context,
                      'Курсы не найдены',
                      'Курстар табылмады',
                      'No courses found',
                    ),
                  ),
                for (final raw in items)
                  _CourseTile(
                    course: raw as Map<String, dynamic>,
                    api: widget.api,
                  ),
                Wrap(
                  spacing: 8,
                  children: [
                    if (_offset > 0)
                      TextButton(
                        onPressed: () => _page(_offset - 20),
                        child: Text(
                          _label(context, 'Назад', 'Артқа', 'Previous'),
                        ),
                      ),
                    if (snapshot.data?['hasMore'] == true && _offset < 10000)
                      TextButton(
                        onPressed: () => _page(_offset + 20),
                        child: Text(
                          _label(
                            context,
                            'Ещё курсы',
                            'Тағы курстар',
                            'More courses',
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _CourseTile extends StatelessWidget {
  const _CourseTile({required this.course, required this.api});

  final Map<String, dynamic> course;
  final KundeApi api;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.menu_book_rounded),
      title: Text(course['title'] as String),
      subtitle: Text(
        [
          course['organization'] as String,
          _price(context, course['priceMinor'] as int),
          if (course['synthetic'] == true)
            _label(
              context,
              'Синтетические данные',
              'Синтетикалық деректер',
              'Synthetic data',
            ),
        ].join('\n'),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => _CourseDetail(api: api, course: course),
        ),
      ),
    ),
  );
}

class _CourseDetail extends StatefulWidget {
  const _CourseDetail({required this.api, required this.course});
  final KundeApi api;
  final Map<String, dynamic> course;

  @override
  State<_CourseDetail> createState() => _CourseDetailState();
}

class _CourseDetailState extends State<_CourseDetail> {
  late Future<Map<String, dynamic>> _result = _load();

  Future<Map<String, dynamic>> _load() =>
      widget.api.loadEducationCourse(widget.course['id'] as String);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.course['title'] as String)),
    body: FutureBuilder(
      future: _result,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data;
        if (data == null) {
          return Center(
            child: _Retry(onRetry: () => setState(() => _result = _load())),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              widget.course['title'] as String,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(widget.course['organization'] as String),
            const SizedBox(height: 12),
            Text(data['description'] as String),
            const SizedBox(height: 16),
            Text(
              _label(context, 'Форматы', 'Форматтар', 'Formats'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            for (final format in data['formats'] as List<dynamic>)
              ListTile(
                title: Text(_format(context, format['format'] as String)),
                subtitle: Text(_price(context, format['priceMinor'] as int)),
              ),
            const SizedBox(height: 16),
            Text(
              _label(context, 'Программа', 'Бағдарлама', 'Curriculum'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            for (final module in data['modules'] as List<dynamic>)
              ExpansionTile(
                title: Text(module['title'] as String),
                children: [
                  for (final lesson in module['lessons'] as List<dynamic>)
                    ListTile(title: Text(lesson['title'] as String)),
                ],
              ),
          ],
        );
      },
    ),
  );
}

class _Retry extends StatelessWidget {
  const _Retry({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        _label(
          context,
          'Каталог недоступен',
          'Каталог қолжетімсіз',
          'Catalog unavailable',
        ),
      ),
      TextButton(
        onPressed: onRetry,
        child: Text(_label(context, 'Повторить', 'Қайталау', 'Retry')),
      ),
    ],
  );
}
