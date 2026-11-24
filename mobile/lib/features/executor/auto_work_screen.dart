import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'package:kunde_models/auto_models.dart' show formatTenge;
import 'package:kunde_auth/auth_repository.dart';
import 'package:kunde_ui/ride_strings.dart';

/// Executor mode AUTO_SPECIALIST: enrollment, availability, nearby on-site requests, accept, arrive, start,
/// price proposal, complete and history. Its approval and categories are separate from Rides and Delivery.
class AutoWorkScreen extends StatefulWidget {
  const AutoWorkScreen(
      {required this.auth,
      this.synthetic = false,
      this.intakeEnabled = true,
      super.key});

  final AuthRepository auth;

  /// Test routing / fixture mode: sends a fixed Almaty point instead of the phone's GPS.
  final bool synthetic;

  /// False when the server switched Auto off: no new jobs can be taken, assigned jobs can still be finished.
  final bool intakeEnabled;

  @override
  State<AutoWorkScreen> createState() => _AutoWorkScreenState();
}

class _AutoWorkScreenState extends State<AutoWorkScreen> {
  static const _root = 'executor/auto';
  final _name = TextEditingController();
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _open = [];
  List<Map<String, dynamic>> _mine = [];
  bool _busy = false;
  bool _loaded = false;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _poll = Timer.periodic(const Duration(seconds: 7), (_) {
      if (ModalRoute.of(context)?.isCurrent == true &&
          _profile != null &&
          !_busy) {
        unawaited(_load());
      }
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _name.dispose();
    super.dispose();
  }

  Future<dynamic> _call(String method, String path,
          {Map<String, dynamic>? body, Set<int> expected = const {200}}) =>
      widget.auth.authorizedJson(method, path, body: body, expected: expected);

  String _message(RideStrings s, Object e) {
    if (e is IdentityApiError) {
      return switch (e.code) {
        'JOB_TAKEN' => s.t('Заявку уже взял другой специалист.',
            'Өтінімді басқа маман алды.', 'Another specialist took this job.'),
        'SPECIALIST_BUSY' => s.t(
            'Сначала завершите текущее задание.',
            'Алдымен ағымдағы тапсырманы аяқтаңыз.',
            'Finish your current job first.'),
        'CATEGORY_NOT_PERMITTED' => s.t(
            'У вас нет допуска к этому виду работ.',
            'Бұл жұмыс түріне рұқсатыңыз жоқ.',
            'You are not approved for this kind of work.'),
        'SPECIALIST_NOT_APPROVED' => s.t(
            'Нужно одобрение администратора.',
            'Әкімшінің мақұлдауы қажет.',
            'Administrator approval is required.'),
        'AUTO_DISABLED' => s.t(
            'Приём новых заявок отключён.',
            'Жаңа өтінімдерді қабылдау өшірулі.',
            'New requests are switched off.'),
        'PRICE_APPROVAL_PENDING' => s.t(
            'Клиент ещё не согласовал цену.',
            'Клиент бағаны әлі келіскен жоқ.',
            'The customer has not approved the price yet.'),
        'JOB_TRANSITION_INVALID' => s.t(
            'Это действие сейчас недоступно.',
            'Бұл әрекет қазір қолжетімсіз.',
            'This action is not available now.'),
        _ => s.error,
      };
    }
    return s.error;
  }

  Future<void> _load([Future<dynamic> Function()? action]) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      if (action != null) _error = null;
    });
    try {
      if (action != null) await action();
      Map<String, dynamic>? profile;
      try {
        profile = await _call('GET', '$_root/profile') as Map<String, dynamic>;
      } on IdentityApiError catch (failure) {
        if (failure.code != 'SPECIALIST_NOT_FOUND') rethrow;
      }
      final open = profile?['online'] == true && widget.intakeEnabled
          ? (await _call('GET', '$_root/jobs/available') as List)
              .cast<Map<String, dynamic>>()
          : <Map<String, dynamic>>[];
      final mine = profile == null
          ? <Map<String, dynamic>>[]
          : (await _call('GET', '$_root/jobs') as List)
              .cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _open = open;
        _mine = mine;
        _loaded = true;
        _error = null;
      });
    } on IdentityApiError catch (failure) {
      if (mounted) {
        setState(() => _error = _message(RideStrings(context), failure));
      }
    } catch (_) {
      if (mounted) setState(() => _error = RideStrings(context).error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendLocation() async {
    double latitude;
    double longitude;
    if (widget.synthetic) {
      latitude = 43.24;
      longitude = 76.92;
    } else {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw IdentityUnavailable();
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        throw IdentityUnavailable();
      }
      final p = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(timeLimit: Duration(seconds: 12)));
      latitude = p.latitude;
      longitude = p.longitude;
    }
    await _call('PUT', '$_root/location',
        body: {'latitude': latitude, 'longitude': longitude}, expected: {204});
  }

  Future<void> _setOnline(bool online) => _load(() async {
        await _call('PUT', '$_root/availability', body: {'online': online});
        if (online) await _sendLocation();
      });

  Future<void> _progress(String id, String action, {int? finalPriceMinor}) =>
      _load(() => _call('POST', '$_root/jobs/$id/progress', body: {
            'action': action,
            if (finalPriceMinor != null) 'finalPriceMinor': finalPriceMinor,
          }));

  Future<void> _proposePrice(String id, RideStrings s) async {
    final tiyn = await showDialog<int>(
        context: context, builder: (_) => _PriceDialog(strings: s));
    if (tiyn != null) {
      await _progress(id, 'PROPOSE_PRICE', finalPriceMinor: tiyn);
    }
  }

  String _category(RideStrings s, String code) => switch (code) {
        'ROADSIDE' =>
          s.t('Выездная помощь', 'Жолдағы көмек', 'Roadside assistance'),
        _ => code,
      };

  String _status(RideStrings s, String status) => switch (status) {
        'PENDING' => s.t('На проверке', 'Тексерілуде', 'Under review'),
        'APPROVED' => s.t('Одобрено', 'Мақұлданды', 'Approved'),
        'BLOCKED' => s.t('Заблокировано', 'Бұғатталды', 'Blocked'),
        'ASSIGNED' => s.t('Назначено', 'Тағайындалды', 'Assigned'),
        'ARRIVED' => s.t('На месте', 'Орнында', 'Arrived'),
        'IN_PROGRESS' => s.t('Выполняется', 'Орындалуда', 'In progress'),
        'COMPLETED' => s.t('Завершено', 'Аяқталды', 'Completed'),
        'CANCELLED' => s.t('Отменено', 'Бас тартылды', 'Cancelled'),
        _ => status,
      };

  String _action(RideStrings s, String a) => switch (a) {
        'ARRIVE' => s.t('Я на месте', 'Келдім', 'I have arrived'),
        'START' => s.t('Начать работы', 'Жұмысты бастау', 'Start work'),
        'PROPOSE_PRICE' =>
          s.t('Предложить цену', 'Бағаны ұсыну', 'Propose price'),
        'COMPLETE' => s.t('Завершить', 'Аяқтау', 'Complete'),
        'RELEASE' => s.t('Отказаться', 'Бас тарту', 'Release job'),
        _ => a,
      };

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    final theme = Theme.of(context);
    final profile = _profile;
    final active = _mine
        .where((j) =>
            const {'ASSIGNED', 'ARRIVED', 'IN_PROGRESS'}.contains(j['status']))
        .toList();
    final history = _mine.where((j) => !active.contains(j)).toList();
    return Scaffold(
      appBar: AppBar(
          title: Text(s.t('Авто-специалист', 'Авто маман', 'Auto specialist'))),
      body: !_loaded && _error == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                if (_error != null)
                  Semantics(
                    liveRegion: true,
                    child: Card(
                        color: theme.colorScheme.errorContainer,
                        child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(_error!))),
                  ),
                if (!widget.intakeEnabled)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(s.t(
                          'Приём новых заявок отключён. Назначенные задания можно завершить.',
                          'Жаңа өтінімдерді қабылдау өшірулі. Тағайындалған тапсырмаларды аяқтауға болады.',
                          'New requests are switched off. Assigned jobs can still be finished.'))),
                if (profile == null) ...[
                  Text(s.t(
                      'Станьте специалистом по выездной помощи. Администратор проверит заявку и назначит допуск по видам работ.',
                      'Жолдағы көмек маманы болыңыз. Әкімші өтінімді тексеріп, жұмыс түрлеріне рұқсат береді.',
                      'Become an on-site specialist. An administrator reviews the request and approves the kinds of work.')),
                  const SizedBox(height: 12),
                  TextField(
                      controller: _name,
                      maxLength: 80,
                      decoration: InputDecoration(
                          labelText: s.t('Имя', 'Аты', 'Name'))),
                  FilledButton(
                      onPressed: _busy
                          ? null
                          : () {
                              final name = _name.text.trim();
                              if (name.isEmpty) return;
                              unawaited(_load(() => _call(
                                  'POST', '$_root/profile',
                                  body: {'name': name})));
                            },
                      child: Text(s.t('Отправить на проверку',
                          'Тексеруге жіберу', 'Submit for review'))),
                ] else ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(profile['name'] as String,
                                style: theme.textTheme.titleLarge),
                            Text(_status(s, profile['status'] as String)),
                            if ((profile['categories'] as List).isNotEmpty)
                              Text((profile['categories'] as List)
                                  .map((c) => _category(s, c as String))
                                  .join(', ')),
                            if (profile['status'] == 'APPROVED')
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(s.t(
                                    'Принимаю заявки',
                                    'Өтінімдерді қабылдаймын',
                                    'Accepting jobs')),
                                value: profile['online'] == true,
                                onChanged: _busy ? null : _setOnline,
                              ),
                          ]),
                    ),
                  ),
                  if (profile['status'] == 'APPROVED' &&
                      profile['online'] == true &&
                      widget.intakeEnabled) ...[
                    const SizedBox(height: 12),
                    Text(
                        s.t('Заявки рядом', 'Жақын өтінімдер',
                            'Nearby requests'),
                        style: theme.textTheme.titleLarge),
                    if (_open.isEmpty)
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(s.t(
                              'Сейчас нет заявок рядом.',
                              'Қазір жақын өтінімдер жоқ.',
                              'No requests nearby right now.'))),
                    for (final j in _open)
                      Card(
                        child: ListTile(
                          title: Text(
                              '${_category(s, j['category'] as String)} · ${j['vehicle']}'),
                          subtitle: Text(
                              '${j['distanceKm']} km · ${s.t('от', 'бастап', 'from')} ${formatTenge(j['priceMinor'] as int)}'
                              '${(j['description'] as String).isEmpty ? '' : '\n${j['description']}'}'),
                          isThreeLine: (j['description'] as String).isNotEmpty,
                          trailing: FilledButton(
                              onPressed: _busy
                                  ? null
                                  : () => _load(() => _call(
                                      'POST', '$_root/jobs/${j['id']}/accept')),
                              child:
                                  Text(s.t('Принять', 'Қабылдау', 'Accept'))),
                        ),
                      ),
                  ],
                  if (active.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                        s.t('Текущее задание', 'Ағымдағы тапсырма',
                            'Current job'),
                        style: theme.textTheme.titleLarge),
                    for (final j in active)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    '${_category(s, j['category'] as String)} · ${j['vehicle']}',
                                    style: theme.textTheme.titleMedium),
                                Text(_status(s, j['status'] as String)),
                                Text('${j['addressText']}'),
                                if ((j['description'] as String).isNotEmpty)
                                  Text('${j['description']}'),
                                Text(
                                    '${s.t('от', 'бастап', 'from')} ${formatTenge(j['priceMinor'] as int)}'),
                                if (j['finalPriceMinor'] != null)
                                  Text(
                                      '${s.t('Итог', 'Қорытынды', 'Final')}: ${formatTenge(j['finalPriceMinor'] as int)}'
                                      '${j['priceApproval'] == 'PENDING' ? ' · ${s.t('ждёт согласия клиента', 'клиент келісімін күтеді', 'waiting for the customer')}' : ''}'),
                                const SizedBox(height: 8),
                                Wrap(spacing: 8, runSpacing: 8, children: [
                                  for (final a in (j['allowedActions'] as List)
                                      .cast<String>())
                                    a == 'RELEASE'
                                        ? OutlinedButton(
                                            onPressed: _busy
                                                ? null
                                                : () => _progress(
                                                    j['id'] as String, a),
                                            child: Text(_action(s, a)))
                                        : FilledButton(
                                            onPressed: _busy
                                                ? null
                                                : () => a == 'PROPOSE_PRICE'
                                                    ? _proposePrice(
                                                        j['id'] as String, s)
                                                    : _progress(
                                                        j['id'] as String, a),
                                            child: Text(_action(s, a))),
                                ]),
                              ]),
                        ),
                      ),
                  ],
                  if (history.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(s.t('История', 'Тарих', 'History'),
                        style: theme.textTheme.titleLarge),
                    for (final j in history)
                      ListTile(
                        title: Text(
                            '${_category(s, j['category'] as String)} · ${j['vehicle']}'),
                        subtitle: Text(_status(s, j['status'] as String) +
                            (j['finalPriceMinor'] == null
                                ? ''
                                : ' · ${formatTenge(j['finalPriceMinor'] as int)}')),
                      ),
                  ],
                ],
              ]),
            ),
    );
  }
}

/// Owns its controller so it is disposed only after the dialog route has fully closed.
class _PriceDialog extends StatefulWidget {
  const _PriceDialog({required this.strings});

  final RideStrings strings;

  @override
  State<_PriceDialog> createState() => _PriceDialogState();
}

class _PriceDialogState extends State<_PriceDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int? get _value {
    final v = int.tryParse(_controller.text.trim());
    return v != null && v >= 0 && v <= 1000000 ? v : null;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final value = _value;
    return AlertDialog(
      title:
          Text(s.t('Итоговая цена, ₸', 'Түпкілікті баға, ₸', 'Final price, ₸')),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
            helperText: s.t(
                'Клиент должен согласовать цену.',
                'Клиент бағамен келісуі керек.',
                'The customer must approve the price.'),
            errorText: _controller.text.isNotEmpty && value == null
                ? s.t(
                    'От 0 до 1 000 000 ₸', '0–1 000 000 ₸', '0 to 1,000,000 ₸')
                : null),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.t('Отмена', 'Бас тарту', 'Cancel'))),
        FilledButton(
            onPressed: value == null
                ? null
                : () => Navigator.pop(context, value * 100),
            child: Text(s.t('Предложить', 'Ұсыну', 'Propose'))),
      ],
    );
  }
}
