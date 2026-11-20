import 'package:flutter/material.dart';

import '../identity/auth_repository.dart';
import '../rides/ride_strings.dart';

/// One switchable feature as the server reports it. The environment is the ceiling: a feature it does not allow cannot be switched here.
class FeatureSwitch {
  const FeatureSwitch(
      {required this.feature,
      required this.allowedByEnvironment,
      required this.enabled,
      required this.effective,
      required this.version,
      this.reason});

  final String feature;
  final bool allowedByEnvironment;
  final bool enabled;
  final bool effective;
  final int version;
  final String? reason;

  factory FeatureSwitch.fromJson(Map<String, dynamic> j) => FeatureSwitch(
      feature: j['feature'] as String,
      allowedByEnvironment: j['allowedByEnvironment'] == true,
      enabled: j['enabled'] == true,
      effective: j['effective'] == true,
      version: (j['version'] as num?)?.toInt() ?? 0,
      reason: j['reason'] as String?);
}

/// Control Center: switch Auto, Rides and Delivery on or off. Needs the ADMIN_GRANTS grant; the server checks it on every request.
class AdminFeaturesScreen extends StatefulWidget {
  const AdminFeaturesScreen({required this.auth, super.key});

  final AuthRepository auth;

  @override
  State<AdminFeaturesScreen> createState() => _AdminFeaturesScreenState();
}

class _AdminFeaturesScreenState extends State<AdminFeaturesScreen> {
  late Future<List<FeatureSwitch>> _features = _load();
  String? _busy;
  String? _message;

  Future<List<FeatureSwitch>> _load() async =>
      ((await widget.auth.authorizedJson('GET', 'admin/features'))
              as List<dynamic>)
          .map((e) => FeatureSwitch.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);

  void _reload() {
    setState(() {
      _features = _load();
    });
  }

  String _title(RideStrings s, String feature) => switch (feature) {
        'HEALTH' => s.t('Здоровье', 'Денсаулық', 'Health'),
        'AUTO' => s.t('Авто', 'Авто', 'Auto'),
        'RIDES' => s.t('Такси', 'Такси', 'Rides'),
        'DELIVERY' => s.t('Доставка', 'Жеткізу', 'Delivery'),
        _ => feature,
      };

  String _status(RideStrings s, FeatureSwitch f) {
    if (!f.allowedByEnvironment) {
      return s.t(
          'Не разрешено окружением: включается только в настройках сервера',
          'Орта рұқсат етпейді: тек сервер баптауларында қосылады',
          'Not allowed by the environment: enabled only in server settings');
    }
    return f.effective
        ? s.t('Включено', 'Қосулы', 'On')
        : s.t('Выключено администратором', 'Әкімші өшірді',
            'Switched off by an administrator');
  }

  String _failure(RideStrings s, Object error) {
    if (error is IdentityApiError) {
      return switch (error.code) {
        'VERSION_CONFLICT' => s.t(
            'Переключатель уже изменили. Список обновлён, повторите.',
            'Ауыстырғыш өзгертілген. Тізім жаңартылды, қайталаңыз.',
            'The switch was changed by someone else. The list was refreshed; retry.'),
        'FEATURE_NOT_ALLOWED_BY_ENVIRONMENT' => s.t(
            'Окружение не разрешает эту функцию.',
            'Орта бұл функцияға рұқсат етпейді.',
            'The environment does not allow this feature.'),
        'REASON_REQUIRED' => s.t(
            'Укажите причину (3–200 символов).',
            'Себебін көрсетіңіз (3–200 таңба).',
            'Enter a reason (3–200 characters).'),
        _ => s.error,
      };
    }
    return s.error;
  }

  Future<void> _toggle(FeatureSwitch f, bool value) async {
    final s = RideStrings(context);
    final reason = await showDialog<String>(
        context: context,
        builder: (_) => _ReasonDialog(
            title:
                '${_title(s, f.feature)}: ${value ? s.t('включить', 'қосу', 'turn on') : s.t('выключить', 'өшіру', 'turn off')}'));
    if (reason == null || !mounted) return;
    setState(() {
      _busy = f.feature;
      _message = null;
    });
    try {
      await widget.auth.authorizedJson('PUT', 'admin/features/${f.feature}',
          body: {
            'enabled': value,
            'reason': reason,
            if (f.version > 0) 'version': f.version
          });
      if (!mounted) return;
      setState(() {
        _busy = null;
        _features = _load();
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = null;
        _message = _failure(s, e);
        _features = _load();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('Функции', 'Функциялар', 'Features'))),
      body: SafeArea(
        child: FutureBuilder<List<FeatureSwitch>>(
          future: _features,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                  child: Semantics(
                      liveRegion: true,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(s.error),
                        TextButton(onPressed: _reload, child: Text(s.retry)),
                      ])));
            }
            final features = snapshot.requireData;
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(padding: const EdgeInsets.all(16), children: [
                  Text(
                      s.t(
                          'Окружение задаёт, что разрешено. Здесь функцию можно выключить и включить обратно; каждое изменение записывается в журнал с причиной.',
                          'Орта нені рұқсат ететінін анықтайды. Мұнда функцияны өшіріп, қайта қосуға болады; әр өзгеріс себебімен журналға жазылады.',
                          'The environment decides what is allowed. Here a feature can be switched off and on again; every change is journaled with a reason.'),
                      style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 12),
                  if (_message != null)
                    Semantics(
                        liveRegion: true,
                        child: Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(_message!,
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error)))),
                  for (final f in features)
                    Card(
                      child: SwitchListTile(
                        key: ValueKey('feature-${f.feature}'),
                        title: Text(_title(s, f.feature)),
                        subtitle: Text([
                          _status(s, f),
                          if (f.reason != null && f.reason!.isNotEmpty)
                            '${s.t('Причина', 'Себебі', 'Reason')}: ${f.reason}'
                        ].join('\n')),
                        isThreeLine: f.reason != null && f.reason!.isNotEmpty,
                        value: f.allowedByEnvironment && f.enabled,
                        onChanged: !f.allowedByEnvironment || _busy != null
                            ? null
                            : (v) => _toggle(f, v),
                      ),
                    ),
                ]),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A dialog with its own controller: it is disposed with the dialog, never while the closing animation still builds.
class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.title});

  final String title;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    final valid = _controller.text.trim().length >= 3;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 200,
        decoration:
            InputDecoration(labelText: s.t('Причина', 'Себебі', 'Reason')),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(s.cancel)),
        FilledButton(
            onPressed: valid
                ? () => Navigator.of(context).pop(_controller.text.trim())
                : null,
            child: Text(s.t('Применить', 'Қолдану', 'Apply'))),
      ],
    );
  }
}
