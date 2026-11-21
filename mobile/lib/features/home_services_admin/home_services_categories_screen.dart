import 'package:flutter/material.dart';

import '../identity/auth_repository.dart';
import '../rides/ride_strings.dart';

const _categoriesPath = 'admin/home-services/categories';
const _pageSize = 20;

class HomeServicesCategoriesScreen extends StatefulWidget {
  const HomeServicesCategoriesScreen({required this.auth, super.key});

  final AuthRepository auth;

  @override
  State<HomeServicesCategoriesScreen> createState() =>
      _HomeServicesCategoriesScreenState();
}

class _HomeServicesCategoriesScreenState
    extends State<HomeServicesCategoriesScreen> {
  int _offset = 0;
  late Future<List<Map<String, dynamic>>> _page = _load();

  Future<List<Map<String, dynamic>>> _load() async {
    final data = await widget.auth.authorizedJson(
      'GET',
      '$_categoriesPath?limit=$_pageSize&offset=$_offset',
    ) as List<dynamic>;
    return data.cast<Map<String, dynamic>>();
  }

  Future<void> _refresh([int? offset]) async {
    setState(() {
      _offset = offset ?? _offset;
      _page = _load();
    });
    try {
      await _page;
    } catch (_) {
      // The FutureBuilder displays the request failure.
    }
  }

  Future<void> _edit([Map<String, dynamic>? category]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _CategoryEditor(auth: widget.auth, category: category),
      ),
    );
    if (mounted && changed == true) await _refresh(category == null ? 0 : null);
  }

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('Дом и быт', 'Үй және тұрмыс', 'Home services')),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _page,
            builder: (context, state) {
              if (state.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final items = state.data ?? [];
              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    if (state.hasError) ...[
                      Text(s.error),
                      TextButton(onPressed: _refresh, child: Text(s.retry)),
                    ] else ...[
                      FilledButton.icon(
                        onPressed: _edit,
                        icon: const Icon(Icons.add),
                        label: Text(
                          s.t(
                            'Добавить категорию',
                            'Санат қосу',
                            'Add category',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (items.isEmpty)
                        Text(
                          s.t(
                            'На этой странице нет категорий',
                            'Бұл бетте санаттар жоқ',
                            'No categories on this page',
                          ),
                        ),
                      for (final category in items)
                        Card(
                          child: ListTile(
                            title: Text(
                              s.t(
                                category['nameRu'] as String,
                                category['nameKk'] as String,
                                category['nameEn'] as String,
                              ),
                            ),
                            subtitle: Text(
                              category['active'] == true
                                  ? s.t('Включена', 'Қосулы', 'Active')
                                  : s.t('Отключена', 'Өшірулі', 'Inactive'),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _edit(category),
                          ),
                        ),
                      Wrap(
                        spacing: 8,
                        children: [
                          if (_offset > 0)
                            TextButton(
                              onPressed: () => _refresh(_offset - _pageSize),
                              child: Text(s.back),
                            ),
                          if (items.length == _pageSize && _offset < 10000)
                            TextButton(
                              onPressed: () => _refresh(_offset + _pageSize),
                              child: Text(s.t('Далее', 'Келесі', 'Next')),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CategoryEditor extends StatefulWidget {
  const _CategoryEditor({required this.auth, this.category});

  final AuthRepository auth;
  final Map<String, dynamic>? category;

  @override
  State<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<_CategoryEditor> {
  final _form = GlobalKey<FormState>();
  late final _fields = {
    for (final key in [
      'code',
      'nameRu',
      'nameKk',
      'nameEn',
      'icon',
      'sortOrder',
    ])
      key: TextEditingController(
        text: widget.category?[key]?.toString() ??
            (key == 'sortOrder' ? '0' : ''),
      ),
    'reason': TextEditingController(),
  };
  late bool _active = widget.category?['active'] == true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _save(RideStrings s) async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final values = _fields.map(
      (key, field) => MapEntry(key, field.text.trim()),
    );
    final code = values.remove('code');
    try {
      await widget.auth.authorizedJson(
        'PUT',
        '$_categoriesPath/$code',
        expected: const {200, 201},
        body: {
          ...values,
          'sortOrder': int.parse(values['sortOrder']!),
          'active': _active,
          'expectedVersion': widget.category?['version'] ?? 0,
        },
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error is IdentityApiError && error.code == 'VERSION_CONFLICT'
            ? s.t(
                'Категорию изменили. Вернитесь к списку и обновите его.',
                'Санат өзгертілді. Тізімге оралып, оны жаңартыңыз.',
                'The category changed. Return to the list and refresh it.',
              )
            : s.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    final editing = widget.category != null;
    final theme = Theme.of(context);
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            editing
                ? s.t('Изменить категорию', 'Санатты өзгерту', 'Edit category')
                : s.t('Добавить категорию', 'Санат қосу', 'Add category'),
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (final (key, label, max) in [
                    ('code', s.t('Код', 'Код', 'Code'), 32),
                    (
                      'nameRu',
                      s.t('Название RU', 'Орысша атауы', 'Russian name'),
                      120,
                    ),
                    (
                      'nameKk',
                      s.t('Название KK', 'Қазақша атауы', 'Kazakh name'),
                      120,
                    ),
                    (
                      'nameEn',
                      s.t('Название EN', 'Ағылшынша атауы', 'English name'),
                      120,
                    ),
                    (
                      'icon',
                      s.t('Код иконки', 'Белгіше коды', 'Icon code'),
                      40
                    ),
                    ('sortOrder', s.t('Порядок', 'Реті', 'Display order'), 10),
                    (
                      'reason',
                      s.t(
                        'Причина изменения',
                        'Өзгерту себебі',
                        'Reason for change',
                      ),
                      200,
                    ),
                  ]) ...[
                    TextFormField(
                      key: ValueKey(key),
                      controller: _fields[key],
                      enabled: !_busy,
                      readOnly: key == 'code' && editing,
                      decoration: InputDecoration(labelText: label),
                      keyboardType:
                          key == 'sortOrder' ? TextInputType.number : null,
                      validator: (raw) {
                        final value = raw?.trim() ?? '';
                        final valid = switch (key) {
                          'code' => RegExp(
                              r'^[A-Z][A-Z0-9_]{1,31}$',
                            ).hasMatch(value),
                          'icon' => RegExp(
                              r'^[a-z][a-z0-9_]{1,39}$',
                            ).hasMatch(value),
                          'sortOrder' =>
                            RegExp(r'^\d{1,10}$').hasMatch(value) &&
                                int.parse(value) <= 2147483647,
                          'reason' => value.length >= 3 && value.length <= max,
                          _ => value.isNotEmpty && value.length <= max,
                        };
                        return valid
                            ? null
                            : s.t(
                                'Проверьте значение',
                                'Мәнді тексеріңіз',
                                'Check this value',
                              );
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      s.t(
                        'Показывать в каталоге',
                        'Каталогта көрсету',
                        'Show in catalog',
                      ),
                    ),
                    value: _active,
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _active = value),
                  ),
                  if (_error case final error?)
                    Text(error,
                        style: TextStyle(color: theme.colorScheme.error)),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : () => _save(s),
                    child: Text(
                      _busy
                          ? s.t('Сохранение…', 'Сақталуда…', 'Saving…')
                          : s.t('Сохранить', 'Сақтау', 'Save'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
