import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/error_text.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/partner_api.dart';
import '../../data/partner_operations.dart';

/// «Дом и быт»: masters of the partner's cleaning venues and the one-time invite codes they link in Executor with.
/// Who may change them is the server's decision (OWNER/MANAGER); this screen only hides what a role can not do.
class HomeServicesMastersScreen extends StatefulWidget {
  const HomeServicesMastersScreen(
      {required this.api,
      required this.partnerId,
      required this.canManage,
      this.ops,
      super.key});

  final PartnerApi api;
  final String partnerId;
  final bool canManage;

  /// Lists the partner's venues for the «new master» form; without it masters can be reissued and retired, not created.
  final PartnerOperations? ops;

  @override
  State<HomeServicesMastersScreen> createState() =>
      _HomeServicesMastersScreenState();
}

class _HomeServicesMastersScreenState extends State<HomeServicesMastersScreen> {
  String get _root =>
      'partner/partners/${Uri.encodeComponent(widget.partnerId)}/home-services/masters';
  late Future<List<Map<String, dynamic>>> _masters = widget.api.getList(_root);

  Future<void> _reload() async {
    setState(() {
      _masters = widget.api.getList(_root);
    });
    try {
      await _masters;
    } catch (_) {
      // The FutureBuilder displays the failure.
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    final s = S.of(context);
    try {
      await action();
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(errorText(s, error))));
    }
    if (mounted) await _reload();
  }

  Future<void> _create() async {
    final created = await showDialog<bool>(
        context: context,
        builder: (_) => _NewMasterDialog(
            ops: widget.ops!, api: widget.api, root: _root));
    if (created == true && mounted) await _reload();
  }

  Future<void> _reissue(Map<String, dynamic> master) => _run(() async {
        await widget.api.postMap('$_root/${master['id']}/invite', {});
      });

  Future<void> _deactivate(Map<String, dynamic> master) async {
    final locale = Localizations.localeOf(context);
    final t = _t(locale);
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
              title: Text(t('Вывести из работы?', 'Жұмыстан шығару керек пе?',
                  'Retire this master?')),
              content: Text('${master['name']}'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(dialog).pop(false),
                    child: Text(t('Отмена', 'Бас тарту', 'Cancel'))),
                TextButton(
                    key: const ValueKey('confirm-deactivate'),
                    onPressed: () => Navigator.of(dialog).pop(true),
                    child: Text(t('Вывести', 'Шығару', 'Retire'))),
              ],
            ));
    if (confirmed != true || !mounted) return;
    await _run(() async {
      await widget.api.postJson('$_root/${master['id']}/deactivate', {});
    });
  }

  static String Function(String, String, String) _t(Locale l) =>
      (String ru, String kk, String en) => switch (l.languageCode) {
            'kk' => kk,
            'en' => en,
            _ => ru,
          };

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = _t(Localizations.localeOf(context));
    return Scaffold(
      appBar: AppBar(
          title: Text(t('Дом и быт: мастера', 'Үй және тұрмыс: шеберлер',
              'Home services: masters'))),
      floatingActionButton: widget.canManage && widget.ops != null
          ? FloatingActionButton.extended(
              key: const ValueKey('create-master'),
              onPressed: _create,
              icon: const Icon(Icons.person_add_alt_1),
              label: Text(t('Новый мастер', 'Жаңа шебер', 'New master')),
            )
          : null,
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _masters,
        builder: (context, state) {
          if (state.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.hasError) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(errorText(s, state.error!)),
                TextButton(
                    onPressed: _reload,
                    child: Text(t('Повторить', 'Қайталау', 'Retry'))),
              ]),
            );
          }
          final masters = state.data!;
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(Gap.lg),
              children: [
                if (masters.isEmpty)
                  Text(t('Мастеров пока нет', 'Шеберлер әлі жоқ',
                      'No masters yet')),
                for (final master in masters)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(Gap.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${master['name']}',
                              style: Theme.of(context).textTheme.titleMedium),
                          Text('${master['venueName']}'),
                          if (master['linked'] == true)
                            Text(
                                key: ValueKey('linked-${master['id']}'),
                                t('Вошёл в приложение мастера',
                                    'Шебер қосымшасына кірді',
                                    'Signed in to the master app'))
                          else if (master['inviteCode'] != null)
                            Row(children: [
                              Expanded(
                                  child: SelectableText(
                                      key: ValueKey('code-${master['id']}'),
                                      '${master['inviteCode']}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge)),
                              IconButton(
                                key: ValueKey('copy-${master['id']}'),
                                tooltip: t('Скопировать код', 'Кодты көшіру',
                                    'Copy code'),
                                icon: const Icon(Icons.copy),
                                onPressed: () => Clipboard.setData(ClipboardData(
                                    text: '${master['inviteCode']}')),
                              ),
                            ]),
                          if (widget.canManage)
                            Wrap(spacing: Gap.sm, children: [
                              if (master['linked'] != true)
                                TextButton(
                                  key: ValueKey('reissue-${master['id']}'),
                                  onPressed: () => _reissue(master),
                                  child: Text(t('Новый код', 'Жаңа код',
                                      'New code')),
                                ),
                              TextButton(
                                key: ValueKey('deactivate-${master['id']}'),
                                onPressed: () => _deactivate(master),
                                child: Text(t('Вывести из работы',
                                    'Жұмыстан шығару', 'Retire')),
                              ),
                            ]),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Name and venue of a new master; the server answers with the invite code, which then shows in the list.
class _NewMasterDialog extends StatefulWidget {
  const _NewMasterDialog(
      {required this.ops, required this.api, required this.root});

  final PartnerOperations ops;
  final PartnerApi api;
  final String root;

  @override
  State<_NewMasterDialog> createState() => _NewMasterDialogState();
}

class _NewMasterDialogState extends State<_NewMasterDialog> {
  late final Future<List<Venue>> _venues = widget.ops
      .venues()
      .then((all) => all.where((v) => v.category == 'CLEANING').toList());
  final _name = TextEditingController();
  Venue? _venue;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _valid => _venue != null && _name.text.trim().isNotEmpty;

  Future<void> _save() async {
    if (!_valid || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final nav = Navigator.of(context);
    final s = S.of(context);
    try {
      await widget.api.postMap(
          widget.root, {'venueId': _venue!.id, 'name': _name.text.trim()});
      if (!mounted) return;
      nav.pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = errorText(s, error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _HomeServicesMastersScreenState._t(Localizations.localeOf(context));
    return AlertDialog(
      title: Text(t('Новый мастер', 'Жаңа шебер', 'New master')),
      content: FutureBuilder<List<Venue>>(
        future: _venues,
        builder: (context, state) {
          if (state.connectionState != ConnectionState.done) {
            return const SizedBox(
                height: 64, child: Center(child: CircularProgressIndicator()));
          }
          if (state.hasError) {
            return Text(t('Не удалось загрузить', 'Жүктеу мүмкін болмады',
                'Could not load'));
          }
          final venues = state.data!;
          if (venues.isEmpty) {
            return Text(t('Нет площадки уборки', 'Тазалау алаңы жоқ',
                'No cleaning venue'));
          }
          return Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<Venue>(
              key: const ValueKey('master-venue'),
              initialValue: _venue,
              decoration: InputDecoration(
                  labelText: t('Площадка', 'Алаң', 'Venue')),
              items: [
                for (final v in venues)
                  DropdownMenuItem(value: v, child: Text(v.name)),
              ],
              onChanged: (v) => setState(() => _venue = v),
            ),
            TextField(
              key: const ValueKey('master-name'),
              controller: _name,
              maxLength: 120,
              decoration: InputDecoration(
                  labelText: t('Имя мастера', 'Шебердің аты', 'Master name')),
              onChanged: (_) => setState(() {}),
            ),
            if (_error != null) Text(_error!),
          ]);
        },
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t('Отмена', 'Бас тарту', 'Cancel'))),
        TextButton(
            key: const ValueKey('save-master'),
            onPressed: _valid && !_busy ? _save : null,
            child: Text(t('Создать', 'Жасау', 'Create'))),
      ],
    );
  }
}
