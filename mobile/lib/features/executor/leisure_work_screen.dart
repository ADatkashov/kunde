import 'package:flutter/material.dart';

import '../identity/auth_repository.dart';
import '../rides/ride_strings.dart';

/// Executor mode for Leisure events that really need a person (guide, host, instructor, animator, organiser): offers made by a partner,
/// accept or decline, start within the work window, complete, cancel before the start, and history. The server decides every step.
class LeisureWorkScreen extends StatefulWidget {
  const LeisureWorkScreen({required this.auth, super.key});

  final AuthRepository auth;

  @override
  State<LeisureWorkScreen> createState() => _LeisureWorkScreenState();
}

class _LeisureWorkScreenState extends State<LeisureWorkScreen>
    with SingleTickerProviderStateMixin {
  static const _root = 'executor/leisure/assignments';
  late final TabController _tabs = TabController(length: 2, vsync: this);
  late Future<List<Map<String, dynamic>>> _active = _load('active');
  late Future<List<Map<String, dynamic>>> _history = _load('history');
  bool _busy = false;

  Future<List<Map<String, dynamic>>> _load(String scope) async =>
      (await widget.auth.authorizedJson('GET', '$_root?scope=$scope') as List)
          .cast<Map<String, dynamic>>();

  void _reload() => setState(() {
        _active = _load('active');
        _history = _load('history');
      });

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _step(Map<String, dynamic> a, String step) async {
    final s = RideStrings(context);
    setState(() => _busy = true);
    try {
      await widget.auth.authorizedJson('POST', '$_root/${a['id']}/step',
          body: {'step': step});
      if (mounted) _reload();
    } on IdentityApiError catch (e) {
      if (!mounted) return;
      final text = e.code == 'OUTSIDE_WORK_WINDOW'
          ? s.t(
              'Начать можно за 2 часа до старта и до конца сеанса',
              'Бастауға сеанс басталуына 2 сағат қалғаннан бастап сеанс аяқталғанға дейін болады',
              'You can start from 2 hours before the session until it ends')
          : s.t('Действие сейчас недоступно', 'Әрекет қазір қолжетімсіз',
              'This step is not possible now');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(s.t('Нет соединения', 'Байланыс жоқ', 'No connection'))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _when(String iso) {
    final m = RegExp(r'^\d{4}-(\d{2})-(\d{2})T(\d{2}):(\d{2})').firstMatch(iso);
    return m == null ? iso : '${m[2]}.${m[1]} ${m[3]}:${m[4]}';
  }

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    final theme = Theme.of(context);
    String roleName(String r) => switch (r) {
          'GUIDE' => s.t('Гид', 'Гид', 'Guide'),
          'HOST' => s.t('Ведущий', 'Жүргізуші', 'Host'),
          'INSTRUCTOR' => s.t('Инструктор', 'Нұсқаушы', 'Instructor'),
          'ANIMATOR' => s.t('Аниматор', 'Аниматор', 'Animator'),
          _ => s.t('Организатор', 'Ұйымдастырушы', 'Organiser'),
        };
    String statusName(String st) => switch (st) {
          'OFFERED' => s.t('Предложено', 'Ұсынылды', 'Offered'),
          'ACCEPTED' => s.t('Принято', 'Қабылданды', 'Accepted'),
          'STARTED' => s.t('В работе', 'Жұмыста', 'In progress'),
          'COMPLETED' => s.t('Завершено', 'Аяқталды', 'Completed'),
          'DECLINED' => s.t('Отклонено', 'Қабылданбады', 'Declined'),
          _ => s.t('Отменено', 'Бас тартылды', 'Cancelled'),
        };
    Widget list(Future<List<Map<String, dynamic>>> future, bool actions) =>
        FutureBuilder<List<Map<String, dynamic>>>(
          future: future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(
                  child: FilledButton(
                      onPressed: _reload,
                      child: Text(s.t('Повторить', 'Қайталау', 'Retry'))));
            }
            final rows = snap.data!;
            if (rows.isEmpty) {
              return Center(
                  child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                          s.t(
                              'Заданий пока нет. Организатор назначит вас на мероприятие.',
                              'Әзірге тапсырма жоқ. Ұйымдастырушы сізді іс-шараға тағайындайды.',
                              'No assignments yet. An organiser will assign you to an event.'),
                          textAlign: TextAlign.center)));
            }
            return RefreshIndicator(
              onRefresh: () async {
                _reload();
                await future;
              },
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: rows.length,
                itemBuilder: (_, i) {
                  final a = rows[i];
                  final st = '${a['status']}';
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Expanded(
                                  child: Text('${a['eventTitle']}',
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                              fontWeight: FontWeight.w800))),
                              Text(statusName(st),
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: theme.colorScheme.primary)),
                            ]),
                            Text(
                                '${roleName('${a['role']}')} · ${_when('${a['startsAt']}')} – ${_when('${a['endsAt']}').split(' ').last}',
                                style: theme.textTheme.bodySmall),
                            Text('${a['venueName']}, ${a['venueAddress']}',
                                style: theme.textTheme.bodySmall),
                            Text(
                                '${s.t('Гостей', 'Қонақ', 'Guests')}: ${a['guests']}',
                                style: theme.textTheme.bodySmall),
                            if (a['note'] != null)
                              Text('${a['note']}',
                                  style: theme.textTheme.bodySmall),
                            if (actions) ...[
                              const SizedBox(height: 8),
                              Wrap(spacing: 8, runSpacing: 4, children: [
                                if (st == 'OFFERED')
                                  FilledButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _step(a, 'ACCEPT'),
                                      child: Text(s.t(
                                          'Принять', 'Қабылдау', 'Accept'))),
                                if (st == 'OFFERED')
                                  OutlinedButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _step(a, 'DECLINE'),
                                      child: Text(s.t('Отказаться', 'Бас тарту',
                                          'Decline'))),
                                if (st == 'ACCEPTED')
                                  FilledButton(
                                      onPressed: _busy || a['canStart'] != true
                                          ? null
                                          : () => _step(a, 'START'),
                                      child: Text(
                                          s.t('Начать', 'Бастау', 'Start'))),
                                if (st == 'ACCEPTED')
                                  OutlinedButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _step(a, 'CANCEL'),
                                      child: Text(s.t(
                                          'Отменить', 'Болдырмау', 'Cancel'))),
                                if (st == 'STARTED')
                                  FilledButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _step(a, 'COMPLETE'),
                                      child: Text(s.t(
                                          'Завершить', 'Аяқтау', 'Complete'))),
                              ]),
                            ],
                          ]),
                    ),
                  );
                },
              ),
            );
          },
        );
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('Мероприятия', 'Іс-шаралар', 'Events')),
        bottom: TabBar(controller: _tabs, tabs: [
          Tab(text: s.t('Актуальные', 'Өзекті', 'Active')),
          Tab(text: s.t('История', 'Тарих', 'History'))
        ]),
      ),
      body: TabBarView(
          controller: _tabs,
          children: [list(_active, true), list(_history, false)]),
    );
  }
}
