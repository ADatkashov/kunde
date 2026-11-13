import 'package:flutter/material.dart';
import 'auth_repository.dart';
import 'consent_presentation.dart';

/// Approved policies only. The server is authoritative for consent state.
class ConsentPanel extends StatefulWidget {
  const ConsentPanel({required this.auth, super.key});
  final AuthRepository auth;

  @override
  State<ConsentPanel> createState() => _ConsentPanelState();
}

class _ConsentPanelState extends State<ConsentPanel> {
  late Future<List<Map<String, dynamic>>> _policies;
  String? _pending;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _policies = widget.auth.consents();

  String _translate(String ru, String kk, String en) {
    final locale = Localizations.localeOf(context).languageCode;
    return locale == 'kk'
        ? kk
        : locale == 'en'
            ? en
            : ru;
  }

  String get _noTextNotice => _translate(
      'Текст политики пока недоступен в приложении. Документ определяется контрольной суммой SHA-256.',
      'Саясат мәтіні әзірге қолданбада қолжетімсіз. Құжат SHA-256 бақылау сомасымен анықталады.',
      'The policy text is not available in the app yet. The document is identified by its SHA-256 checksum.');

  String _fallbackNotice(String locale) => _translate(
      'Версия на вашем языке недоступна. Документ на языке: ${languageName(locale)}.',
      'Сіздің тіліңізде нұсқа қолжетімсіз. Құжат тілі: ${languageName(locale)}.',
      'No version in your language. The document is in: ${languageName(locale)}.');

  Future<void> _change(Map<String, dynamic> policy, bool grant) async {
    final id = policy['policyId'] as String;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_translate(
            'Подтвердить действие', 'Әрекетті растау', 'Confirm action')),
        content: Text(grant
            ? '${_translate('Предоставить согласие для этой версии политики?', 'Осы саясат нұсқасына келісім бересіз бе?', 'Grant consent to this policy version?')}\n\n$_noTextNotice'
            : _translate(
                'Отозвать согласие для этой версии политики?',
                'Осы саясат нұсқасына келісімді қайтарып аласыз ба?',
                'Withdraw consent for this policy version?')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_translate('Отмена', 'Бас тарту', 'Cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(_translate('Подтвердить', 'Растау', 'Confirm'))),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _pending = id);
    try {
      await widget.auth.setConsent(id, grant);
      if (mounted) setState(_reload);
    } on SessionExpired {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_translate(
              'Сессия истекла', 'Сессия аяқталды', 'Session expired')),
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_translate('Не удалось обновить согласие',
              'Келісімді жаңарту мүмкін болмады', 'Could not update consent')),
        ));
      }
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_translate('Согласия', 'Келісімдер', 'Consents'),
              style: Theme.of(context).textTheme.titleLarge),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _policies,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const LinearProgressIndicator();
              }
              if (snapshot.hasError) {
                return TextButton(
                  onPressed: () => setState(_reload),
                  child: Text(_translate('Ошибка загрузки — повторить',
                      'Жүктеу қатесі — қайталау', 'Loading failed — retry')),
                );
              }
              final policies = snapshot.data ?? [];
              if (policies.isEmpty) {
                return Text(_translate('Нет утверждённых политик',
                    'Бекітілген саясаттар жоқ', 'No approved policies'));
              }
              final language = Localizations.localeOf(context).languageCode;
              return Column(
                children: [
                  for (final entry in presentConsents(policies, language))
                    SwitchListTile(
                      key: ValueKey(entry.policy['policyId']),
                      title: Text(entry.policy['purpose'] as String),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${entry.policy['policyVersion']} · '
                              '${languageName(entry.policy['locale'] as String)}'),
                          if (entry.languageFallback)
                            Text(_fallbackNotice(
                                entry.policy['locale'] as String)),
                          Text(_noTextNotice),
                          Text('SHA-256: ${entry.policy['documentSha256']}'),
                        ],
                      ),
                      value: entry.policy['granted'] == true,
                      onChanged: _pending != null
                          ? null
                          : (value) => _change(entry.policy, value),
                    ),
                ],
              );
            },
          ),
        ],
      );
}
