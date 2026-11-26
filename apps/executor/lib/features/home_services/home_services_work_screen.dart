import 'package:flutter/material.dart';

import 'package:kunde_auth/auth_repository.dart';
import 'package:kunde_ui/ride_strings.dart';

const _root = 'executor/home-services';

/// KUNDE Executor for a Home Services master: link by invite code, then walk each visit in order —
/// on the way (with an ETA), arrived, started, finished. The server enforces the order and who may do it.
class HomeServicesWorkScreen extends StatefulWidget {
  const HomeServicesWorkScreen({required this.auth, super.key});

  final AuthRepository auth;

  /// The one next action a job offers, from its booking [status] and visit [stage].
  static String? nextAction(String status, String? stage) =>
      switch ((status, stage)) {
        ('CONFIRMED', null) => 'EN_ROUTE',
        ('CONFIRMED', 'EN_ROUTE') => 'ARRIVED',
        ('CONFIRMED', 'ARRIVED') => 'START',
        ('IN_PROGRESS', _) => 'COMPLETE',
        _ => null,
      };

  @override
  State<HomeServicesWorkScreen> createState() => _HomeServicesWorkScreenState();
}

class _HomeServicesWorkScreenState extends State<HomeServicesWorkScreen> {
  late Future<List<Map<String, dynamic>>> _jobs = _load();
  final _code = TextEditingController();
  final _eta = TextEditingController(text: '20');
  bool _busy = false;
  String? _error;

  Future<List<Map<String, dynamic>>> _load() async =>
      ((await widget.auth.authorizedJson('GET', '$_root/jobs'))
              as List<dynamic>)
          .cast<Map<String, dynamic>>();

  void _reload() => setState(() {
        _jobs = _load();
      });

  @override
  void dispose() {
    _code.dispose();
    _eta.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    final s = RideStrings(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) _reload();
    } on IdentityApiError catch (e) {
      _error = e.code == 'JOB_STATE_INVALID'
          ? s.t(
              'Действие сейчас недоступно: обновите список',
              'Әрекет қазір қолжетімсіз: тізімді жаңартыңыз',
              'Action not available now: refresh the list')
          : s.error;
      if (mounted) _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _link() => _run(() async {
        await widget.auth.authorizedJson('POST', '$_root/link',
            body: {'code': _code.text.trim()}, expected: const {200, 204});
      });

  Future<void> _act(Map<String, dynamic> job, String action) => _run(() async {
        final id = job['id'];
        switch (action) {
          case 'EN_ROUTE':
            await widget.auth
                .authorizedJson('PUT', '$_root/jobs/$id/stage', body: {
              'stage': 'EN_ROUTE',
              if (int.tryParse(_eta.text.trim()) != null)
                'etaMinutes': int.parse(_eta.text.trim()),
            });
          case 'ARRIVED':
            await widget.auth.authorizedJson('PUT', '$_root/jobs/$id/stage',
                body: {'stage': 'ARRIVED'});
          case 'START':
            await widget.auth.authorizedJson('POST', '$_root/jobs/$id/start');
          case 'COMPLETE':
            await widget.auth
                .authorizedJson('POST', '$_root/jobs/$id/complete');
        }
      });

  String _label(RideStrings s, String action) => switch (action) {
        'EN_ROUTE' => s.t('Выехал', 'Шықтым', 'On my way'),
        'ARRIVED' => s.t('Прибыл на место', 'Жеттім', 'Arrived'),
        'START' => s.t('Начать работу', 'Жұмысты бастау', 'Start work'),
        _ => s.t('Завершить', 'Аяқтау', 'Finish'),
      };

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    return Scaffold(
      appBar: AppBar(
          title: Text(s.t('Дом и быт: мои заказы',
              'Үй және тұрмыс: тапсырыстарым', 'Home services: my jobs'))),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _jobs,
        builder: (context, state) {
          if (state.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final err = state.error;
          if (err is IdentityApiError && err.code == 'NOT_A_MASTER') {
            return _linkForm(s);
          }
          if (state.hasError) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(s.error),
                TextButton(onPressed: _reload, child: Text(s.retry)),
              ]),
            );
          }
          final jobs = state.data!;
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                if (jobs.isEmpty)
                  Text(s.t('Ближайших заказов нет', 'Таяу тапсырыстар жоқ',
                      'No upcoming jobs')),
                if (jobs.isNotEmpty)
                  TextField(
                    key: const ValueKey('eta'),
                    controller: _eta,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        labelText: s.t('Время в пути, мин', 'Жолда, мин',
                            'Travel time, min')),
                  ),
                for (final job in jobs)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${job['serviceName']}',
                              style: Theme.of(context).textTheme.titleMedium),
                          Text('${job['addressText'] ?? ''}'),
                          Text('${job['startsAt']}'.replaceFirst('T', ' ')),
                          if (HomeServicesWorkScreen.nextAction(
                                  '${job['status']}',
                                  job['stage'] as String?) !=
                              null)
                            Builder(builder: (context) {
                              final action = HomeServicesWorkScreen.nextAction(
                                  '${job['status']}', job['stage'] as String?)!;
                              return FilledButton(
                                key: ValueKey(
                                    '${action.toLowerCase()}-${job['id']}'),
                                onPressed:
                                    _busy ? null : () => _act(job, action),
                                child: Text(_label(s, action)),
                              );
                            }),
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

  Widget _linkForm(RideStrings s) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.t(
              'Введите код-приглашение от вашей компании',
              'Компаниядан алған шақыру кодын енгізіңіз',
              'Enter the invite code from your company')),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('code'),
            controller: _code,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(labelText: s.t('Код', 'Код', 'Code')),
          ),
          if (_error != null)
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 12),
          FilledButton(
            key: const ValueKey('link'),
            onPressed: _busy ? null : _link,
            child: Text(s.t('Привязать', 'Байлау', 'Link')),
          ),
        ]),
      );
}
