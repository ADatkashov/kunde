import 'dart:math';

import 'package:flutter/material.dart';
import 'auth_repository.dart';

/// Consumer support cases (SUP-001). Cases are not linked to orders yet and no
/// response time is promised: the server records the request, nothing more.
class SupportPanel extends StatefulWidget {
  const SupportPanel({required this.auth, super.key});
  final AuthRepository auth;

  @override
  State<SupportPanel> createState() => _SupportPanelState();
}

class _SupportPanelState extends State<SupportPanel> {
  late Future<List<Map<String, dynamic>>> _cases;
  String? _pending;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  // Block body: an arrow would return the Future and make setState(_reload) throw.
  void _reload() {
    _cases = widget.auth.supportCases();
  }

  String _t(String ru, String kk, String en) {
    final locale = Localizations.localeOf(context).languageCode;
    return locale == 'kk'
        ? kk
        : locale == 'en'
            ? en
            : ru;
  }

  String _category(String code) => switch (code) {
        'ACCOUNT' => _t('Аккаунт', 'Аккаунт', 'Account'),
        'PRIVACY' => _t('Конфиденциальность', 'Құпиялылық', 'Privacy'),
        'APP_PROBLEM' =>
          _t('Проблема в приложении', 'Қолданба ақауы', 'App problem'),
        _ => _t('Общий вопрос', 'Жалпы сұрақ', 'General question'),
      };

  String _status(String code) => code == 'ESCALATION_REQUESTED'
      ? _t('Запрос на эскалацию отправлен', 'Эскалацияға сұрау жіберілді',
          'Escalation requested')
      : _t('Открыто', 'Ашық', 'Open');

  void _toast(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  void _failure(Object error, String generic) {
    if (!mounted) return;
    _toast(error is SessionExpired
        ? _t('Сессия истекла', 'Сессия аяқталды', 'Session expired')
        : generic);
  }

  Future<void> _open() async {
    final draft = await showDialog<({String category, String message})>(
      context: context,
      builder: (context) => _NewCaseDialog(translate: _t, category: _category),
    );
    if (draft == null || !mounted) return;
    // One key per submission: a retry after a timeout must not duplicate it.
    final key = _newKey();
    setState(() => _pending = 'new');
    try {
      await widget.auth.openSupportCase(
          category: draft.category,
          message: draft.message,
          idempotencyKey: key);
      if (mounted) setState(_reload);
    } catch (error) {
      _failure(
          error,
          error is IdentityApiError && error.status == 409
              ? _t('Слишком много обращений', 'Өтініштер тым көп',
                  'Too many support requests')
              : _t(
                  'Не удалось отправить обращение. Повторите позже.',
                  'Өтінішті жіберу мүмкін болмады. Кейінірек қайталаңыз.',
                  'Could not send the request. Try again later.'));
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  Future<void> _escalate(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('Запросить эскалацию?', 'Эскалацияны сұрау керек пе?',
            'Request escalation?')),
        content: Text(_t(
            'Мы запишем ваш запрос. Срок ответа не гарантируется.',
            'Біз сіздің сұрауыңызды жазамыз. Жауап мерзімі кепілдендірілмейді.',
            'We will record your request. No response time is guaranteed.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_t('Отмена', 'Бас тарту', 'Cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(_t('Запросить', 'Сұрау', 'Request'))),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _pending = id);
    try {
      await widget.auth.requestSupportEscalation(id);
      if (mounted) setState(_reload);
    } catch (error) {
      _failure(
          error,
          _t('Не удалось отправить запрос', 'Сұрауды жіберу мүмкін болмады',
              'Could not send the request'));
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  static String _newKey() {
    final random = Random.secure();
    return List.generate(32, (_) => random.nextInt(16).toRadixString(16))
        .join();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_t('Поддержка', 'Қолдау', 'Support'),
              style: Theme.of(context).textTheme.titleLarge),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _cases,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const LinearProgressIndicator();
              }
              if (snapshot.hasError) {
                return TextButton(
                  onPressed: () => setState(_reload),
                  child: Text(_t('Ошибка загрузки — повторить',
                      'Жүктеу қатесі — қайталау', 'Loading failed — retry')),
                );
              }
              final cases = snapshot.data ?? [];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (cases.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(_t('Обращений пока нет',
                          'Әзірге өтініштер жоқ', 'No support requests yet')),
                    ),
                  for (final entry in cases)
                    ListTile(
                      key: ValueKey(entry['id']),
                      contentPadding: EdgeInsets.zero,
                      title: Text(_category(entry['category'] as String)),
                      subtitle: Text('${entry['message']}\n'
                          '${_status(entry['status'] as String)}'),
                      isThreeLine: true,
                      trailing: entry['status'] == 'OPEN'
                          ? TextButton(
                              onPressed: _pending != null
                                  ? null
                                  : () => _escalate(entry['id'] as String),
                              child: Text(
                                  _t('Эскалация', 'Эскалация', 'Escalate')),
                            )
                          : null,
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton(
                      onPressed: _pending != null ? null : _open,
                      child: Text(_t('Написать в поддержку',
                          'Қолдау қызметіне жазу', 'Contact support')),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      );
}

class _NewCaseDialog extends StatefulWidget {
  const _NewCaseDialog({required this.translate, required this.category});
  final String Function(String, String, String) translate;
  final String Function(String) category;

  @override
  State<_NewCaseDialog> createState() => _NewCaseDialogState();
}

class _NewCaseDialogState extends State<_NewCaseDialog> {
  final _message = TextEditingController();
  String _selected = 'GENERAL';

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.translate;
    return AlertDialog(
      title: Text(t('Обращение в поддержку', 'Қолдау қызметіне өтініш',
          'Contact support')),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            initialValue: _selected,
            decoration:
                InputDecoration(labelText: t('Тема', 'Тақырып', 'Topic')),
            items: [
              for (final code in AuthRepository.supportCategories)
                DropdownMenuItem(
                    value: code, child: Text(widget.category(code))),
            ],
            onChanged: (value) =>
                setState(() => _selected = value ?? _selected),
          ),
          TextField(
            controller: _message,
            maxLength: 2000,
            minLines: 3,
            maxLines: 6,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
                labelText: t('Сообщение', 'Хабарлама', 'Message')),
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('Отмена', 'Бас тарту', 'Cancel'))),
        FilledButton(
            onPressed: _message.text.trim().isEmpty
                ? null
                : () => Navigator.pop(context,
                    (category: _selected, message: _message.text.trim())),
            child: Text(t('Отправить', 'Жіберу', 'Send'))),
      ],
    );
  }
}
