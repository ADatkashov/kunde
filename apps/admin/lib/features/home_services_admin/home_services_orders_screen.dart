import 'package:flutter/material.dart';

import 'package:kunde_auth/auth_repository.dart';
import 'package:kunde_ui/home_service_reschedule_dialog.dart';
import 'package:kunde_ui/ride_strings.dart';

const _ordersPath = 'admin/home-services/orders';
const _pageSize = 30;
const _statuses = [
  'PENDING',
  'CONFIRMED',
  'IN_PROGRESS',
  'COMPLETED',
  'CANCELLED',
  'NO_SHOW',
];

String _statusLabel(RideStrings s, String status) => switch (status) {
      'PENDING' => s.t('Ожидает', 'Күтуде', 'Pending'),
      'CONFIRMED' => s.t('Подтверждён', 'Расталды', 'Confirmed'),
      'IN_PROGRESS' => s.t('В работе', 'Жұмыста', 'In progress'),
      'COMPLETED' => s.t('Завершён', 'Аяқталды', 'Completed'),
      'CANCELLED' => s.t('Отменён', 'Бас тартылды', 'Cancelled'),
      'NO_SHOW' => s.t('Не явился', 'Келмеді', 'No show'),
      _ => status,
    };

/// Money in tenge from minor units, grouped by thousands: `8 000 ₸`.
String formatTenge(num minor) {
  final whole = (minor / 100).round().toString();
  final grouped = whole.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ' ',
  );
  return '$grouped ₸';
}

String _time(Object? iso) {
  final value = DateTime.tryParse('$iso')?.toLocal();
  if (value == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(value.day)}.${two(value.month)} '
      '${two(value.hour)}:${two(value.minute)}';
}

/// Register of Home Services orders for staff (`HOME_SERVICES_OPERATIONS`): search by number, status filter, paging.
/// The register carries no customer contact data; the order card opens on tap.
class HomeServicesOrdersScreen extends StatefulWidget {
  const HomeServicesOrdersScreen({required this.auth, super.key});

  final AuthRepository auth;

  @override
  State<HomeServicesOrdersScreen> createState() =>
      _HomeServicesOrdersScreenState();
}

class _HomeServicesOrdersScreenState extends State<HomeServicesOrdersScreen> {
  final _search = TextEditingController();
  String? _status;
  int _offset = 0;
  late Future<Map<String, dynamic>> _page = _load();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _load() async {
    final query = <String, String>{
      if (_status != null) 'status': _status!,
      if (_search.text.trim().isNotEmpty) 'q': _search.text.trim(),
      'limit': '$_pageSize',
      'offset': '$_offset',
    };
    final qs = query.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final data = await widget.auth.authorizedJson('GET', '$_ordersPath?$qs');
    return (data as Map).cast<String, dynamic>();
  }

  Future<void> _reload() async {
    setState(() {
      _page = _load();
    });
    try {
      await _page;
    } catch (_) {
      // The FutureBuilder displays the request failure.
    }
  }

  Future<void> _open(Map<String, dynamic> order) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => HomeServicesOrderScreen(
          auth: widget.auth,
          orderId: '${order['id']}',
        ),
      ),
    );
    if (mounted) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          s.t('Дом и быт: заказы', 'Үй және тұрмыс: тапсырыстар',
              'Home services orders'),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                key: const ValueKey('order-search'),
                controller: _search,
                maxLength: 24,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  counterText: '',
                  prefixIcon: const Icon(Icons.search),
                  labelText: s.t('Номер заказа (KND-…)', 'Тапсырыс нөмірі',
                      'Order number (KND-…)'),
                ),
                onSubmitted: (_) {
                  _offset = 0;
                  _reload();
                },
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    key: const ValueKey('status-ALL'),
                    label: Text(s.t('Все', 'Барлығы', 'All')),
                    selected: _status == null,
                    onSelected: (_) {
                      _status = null;
                      _offset = 0;
                      _reload();
                    },
                  ),
                ),
                for (final status in _statuses)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      key: ValueKey('status-$status'),
                      label: Text(_statusLabel(s, status)),
                      selected: _status == status,
                      onSelected: (_) {
                        _status = status;
                        _offset = 0;
                        _reload();
                      },
                    ),
                  ),
              ]),
            ),
            Expanded(
              child: FutureBuilder<Map<String, dynamic>>(
                future: _page,
                builder: (context, state) {
                  if (state.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (state.hasError) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(s.error),
                          TextButton(onPressed: _reload, child: Text(s.retry)),
                        ],
                      ),
                    );
                  }
                  final page = state.data ?? const <String, dynamic>{};
                  final items =
                      ((page['items'] as List?) ?? const []).cast<Map>();
                  final total = (page['total'] as num?)?.toInt() ?? 0;
                  return RefreshIndicator(
                    onRefresh: _reload,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        Text(
                          s.t('Найдено: $total', 'Табылды: $total',
                              'Found: $total'),
                          key: const ValueKey('orders-total'),
                        ),
                        const SizedBox(height: 8),
                        if (items.isEmpty)
                          Text(s.t('Заказов нет', 'Тапсырыс жоқ', 'No orders')),
                        for (final raw in items)
                          _OrderCard(
                            order: raw.cast<String, dynamic>(),
                            onTap: () => _open(raw.cast<String, dynamic>()),
                          ),
                        Wrap(spacing: 8, children: [
                          if (_offset > 0)
                            TextButton(
                              key: const ValueKey('prev-page'),
                              onPressed: () {
                                _offset -= _pageSize;
                                _reload();
                              },
                              child: Text(s.back),
                            ),
                          if (_offset + items.length < total && _offset < 10000)
                            TextButton(
                              key: const ValueKey('next-page'),
                              onPressed: () {
                                _offset += _pageSize;
                                _reload();
                              },
                              child: Text(s.t('Далее', 'Келесі', 'Next')),
                            ),
                        ]),
                      ],
                    ),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

String _masterLabel(RideStrings s, Map<String, dynamic> order) {
  final name = order['masterName'] as String?;
  return name == null || name.isEmpty
      ? s.t('Ожидает назначения', 'Тағайындау күтілуде', 'Awaiting assignment')
      : name;
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.onTap});

  final Map<String, dynamic> order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    return Card(
      child: ListTile(
        key: ValueKey('order-${order['id']}'),
        title: Text('${order['bookingNumber']} · ${order['serviceName']}'),
        subtitle: Text(
          '${order['venueName']} · ${_masterLabel(s, order)}\n'
          '${_time(order['startsAt'])} · '
          '${formatTenge(order['priceMinor'] as num)}',
        ),
        isThreeLine: true,
        trailing: Chip(
          label: Text(_statusLabel(s, '${order['status']}')),
          visualDensity: VisualDensity.compact,
        ),
        onTap: onTap,
      ),
    );
  }
}

/// Order card for staff: address, visit, status history, the staff's own actions and, while the order has not started, cancel and
/// re-assign. Every action needs a reason and is sent with the version the screen saw; a stale screen reloads instead.
class HomeServicesOrderScreen extends StatefulWidget {
  const HomeServicesOrderScreen({
    required this.auth,
    required this.orderId,
    super.key,
  });

  final AuthRepository auth;
  final String orderId;

  @override
  State<HomeServicesOrderScreen> createState() =>
      _HomeServicesOrderScreenState();
}

class _HomeServicesOrderScreenState extends State<HomeServicesOrderScreen> {
  late Future<Map<String, dynamic>> _detail = _load();

  String get _path => '$_ordersPath/${widget.orderId}';

  Future<Map<String, dynamic>> _load() async {
    final data = await widget.auth.authorizedJson('GET', _path);
    return (data as Map).cast<String, dynamic>();
  }

  Future<void> _reload() async {
    setState(() {
      _detail = _load();
    });
    try {
      await _detail;
    } catch (_) {
      // The FutureBuilder displays the request failure.
    }
  }

  Future<void> _act(
    String action,
    Map<String, dynamic> detail, {
    Map<String, dynamic> extra = const {},
    required String reason,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final s = RideStrings(context);
    try {
      await widget.auth.authorizedJson(
        'POST',
        '$_path/$action',
        body: {
          ...extra,
          'expectedVersion': detail['version'],
          'reason': reason,
        },
        expected: const {200, 204},
      );
    } catch (_) {
      messenger.showSnackBar(SnackBar(
        content: Text(s.t(
          'Не удалось выполнить действие. Обновите заказ.',
          'Әрекет орындалмады. Тапсырысты жаңартыңыз.',
          'The action failed. Reload the order.',
        )),
      ));
    }
    if (mounted) await _reload();
  }

  Future<void> _cancel(Map<String, dynamic> detail) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _ReasonDialog(cancel: true),
    );
    if (reason == null || !mounted) return;
    await _act('cancel', detail, reason: reason);
  }

  Future<void> _proposeReschedule(Map<String, dynamic> detail) async {
    final proposal = await showDialog<HomeServiceScheduleProposal>(
      context: context,
      builder: (_) => const HomeServiceRescheduleDialog(),
    );
    if (proposal == null || !mounted) return;
    await _act('reschedule', detail,
        extra: {'startsAt': proposal.startsAt}, reason: proposal.reason);
  }

  Future<void> _reassign(Map<String, dynamic> detail) async {
    final s = RideStrings(context);
    final List<Map<String, dynamic>> masters;
    try {
      final data = await widget.auth.authorizedJson('GET', '$_path/masters');
      masters = (data as List).cast<Map<String, dynamic>>();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.error)));
      return;
    }
    if (!mounted) return;
    final order = (detail['order'] as Map).cast<String, dynamic>();
    final choice = await showDialog<({String masterId, String reason})>(
      context: context,
      builder: (_) => _ReassignDialog(
        masters: masters,
        currentName: '${order['masterName']}',
      ),
    );
    if (choice == null || !mounted) return;
    await _act(
      'reassign',
      detail,
      extra: {'masterId': choice.masterId},
      reason: choice.reason,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('Заказ', 'Тапсырыс', 'Order')),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: FutureBuilder<Map<String, dynamic>>(
            future: _detail,
            builder: (context, state) {
              if (state.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (state.hasError || state.data == null) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(s.error),
                      TextButton(onPressed: _reload, child: Text(s.retry)),
                    ],
                  ),
                );
              }
              return _body(context, s, state.data!);
            },
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, RideStrings s, Map<String, dynamic> d) {
    final order = (d['order'] as Map).cast<String, dynamic>();
    final visit = (d['visit'] as Map?)?.cast<String, dynamic>();
    final history = ((d['history'] as List?) ?? const []).cast<Map>();
    final actions = ((d['adminActions'] as List?) ?? const []).cast<Map>();
    final actionable = d['actionable'] == true;
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '${order['bookingNumber']} · ${order['serviceName']}',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Chip(label: Text(_statusLabel(s, '${order['status']}'))),
        const SizedBox(height: 8),
        _line(s.t('Площадка', 'Алаң', 'Venue'), '${order['venueName']}'),
        _line(s.t('Мастер', 'Шебер', 'Master'), _masterLabel(s, order)),
        _line(s.t('Время', 'Уақыты', 'Time'), _time(order['startsAt'])),
        _line(s.t('Адрес', 'Мекенжай', 'Address'), '${d['addressText'] ?? ''}'),
        if (d['areaSqm'] != null)
          _line(s.t('Площадь', 'Ауданы', 'Area'), '${d['areaSqm']} м²'),
        _line(
          s.t('Стоимость', 'Құны', 'Price'),
          formatTenge(order['priceMinor'] as num),
        ),
        if ((d['comment'] as String?)?.isNotEmpty ?? false)
          _line(s.t('Комментарий', 'Пікір', 'Comment'), '${d['comment']}'),
        if ((d['cancelReason'] as String?)?.isNotEmpty ?? false)
          _line(
            s.t('Причина отмены', 'Бас тарту себебі', 'Cancel reason'),
            '${d['cancelReason']} (${order['cancelledBy']})',
          ),
        if (visit != null)
          _line(
            s.t('Визит', 'Келу', 'Visit'),
            '${visit['stage']}'
            '${visit['etaMinutes'] != null ? ' · ${visit['etaMinutes']} min' : ''}',
          ),
        if (actionable) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.tonal(
              key: const ValueKey('reassign'),
              onPressed: () => _reassign(d),
              child: Text(s.t('Переназначить мастера', 'Шеберді ауыстыру',
                  'Reassign master')),
            ),
            if (order['status'] == 'CONFIRMED')
              FilledButton.tonal(
                key: const ValueKey('propose-reschedule'),
                onPressed: () => _proposeReschedule(d),
                child: Text(s.t('Предложить перенос', 'Ауыстыруды ұсыну',
                    'Propose a change')),
              ),
            FilledButton.tonal(
              key: const ValueKey('cancel'),
              onPressed: () => _cancel(d),
              child: Text(s.t(
                  'Отменить заказ', 'Тапсырыстан бас тарту', 'Cancel order')),
            ),
          ]),
        ] else
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              s.t(
                'Отмена и переназначение доступны только до начала работы.',
                'Бас тарту және ауыстыру жұмыс басталғанға дейін ғана мүмкін.',
                'Cancel and reassign are possible only before work starts.',
              ),
              style: theme.textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 16),
        Text(s.t('История', 'Тарих', 'History'),
            style: theme.textTheme.titleMedium),
        for (final h in history)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
                '${_statusLabel(s, '${h['status']}')} · ${h['actorType']}'),
            subtitle: Text('${_time(h['occurredAt'])}'
                '${(h['reason'] as String?)?.isNotEmpty ?? false ? '\n${h['reason']}' : ''}'),
          ),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
              s.t('Действия персонала', 'Қызметкер әрекеттері',
                  'Staff actions'),
              style: theme.textTheme.titleMedium),
          for (final a in actions)
            ListTile(
              key: ValueKey('admin-action-${a['action']}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${a['action']}'),
              subtitle: Text('${_time(a['occurredAt'])}\n${a['reason']}'),
            ),
        ],
      ],
    );
  }

  Widget _line(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Text(label, style: Theme.of(context).textTheme.bodySmall),
            ),
            Expanded(child: Text(value)),
          ],
        ),
      );
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.cancel});

  final bool cancel;

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
    return AlertDialog(
      title:
          Text(s.t('Отменить заказ', 'Тапсырыстан бас тарту', 'Cancel order')),
      content: TextField(
        key: const ValueKey('reason'),
        controller: _controller,
        maxLength: 200,
        decoration: InputDecoration(
          labelText: s.t('Причина (от 3 символов)', 'Себебі (кемінде 3 таңба)',
              'Reason (3+ characters)'),
        ),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.back),
        ),
        FilledButton(
          key: const ValueKey('confirm'),
          onPressed: _controller.text.trim().length >= 3
              ? () => Navigator.of(context).pop(_controller.text.trim())
              : null,
          child: Text(s.t('Подтвердить', 'Растау', 'Confirm')),
        ),
      ],
    );
  }
}

class _ReassignDialog extends StatefulWidget {
  const _ReassignDialog({required this.masters, required this.currentName});

  final List<Map<String, dynamic>> masters;
  final String currentName;

  @override
  State<_ReassignDialog> createState() => _ReassignDialogState();
}

class _ReassignDialogState extends State<_ReassignDialog> {
  final _controller = TextEditingController();
  String? _masterId;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    final options =
        widget.masters.where((m) => m['name'] != widget.currentName).toList();
    final ready = _masterId != null && _controller.text.trim().length >= 3;
    return AlertDialog(
      title: Text(
          s.t('Переназначить мастера', 'Шеберді ауыстыру', 'Reassign master')),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (options.isEmpty)
            Text(s.t('Нет других мастеров площадки', 'Алаңда басқа шебер жоқ',
                'No other masters at the venue')),
          RadioGroup<String>(
            groupValue: _masterId,
            onChanged: (v) => setState(() => _masterId = v),
            child: Column(children: [
              for (final m in options)
                RadioListTile<String>(
                  key: ValueKey('master-${m['id']}'),
                  value: '${m['id']}',
                  title: Text('${m['name']}'),
                ),
            ]),
          ),
          TextField(
            key: const ValueKey('reason'),
            controller: _controller,
            maxLength: 200,
            decoration: InputDecoration(
              labelText: s.t('Причина (от 3 символов)',
                  'Себебі (кемінде 3 таңба)', 'Reason (3+ characters)'),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.back),
        ),
        FilledButton(
          key: const ValueKey('confirm'),
          onPressed: ready
              ? () => Navigator.of(context).pop(
                    (masterId: _masterId!, reason: _controller.text.trim()),
                  )
              : null,
          child: Text(s.t('Подтвердить', 'Растау', 'Confirm')),
        ),
      ],
    );
  }
}
