import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../identity/auth_repository.dart';
import '../leisure/data/leisure_models.dart' show formatTenge;
import '../rides/ride_strings.dart';

/// Leisure Control Center for administrators: analytics, moderation of venues and events, bookings and tickets, refunds, complaints, categories
/// and the audit journal. Everything goes through `/api/v1/admin/leisure/**`, where the LEISURE_OPERATIONS grant is checked on every request;
/// the screen only presents what the server returns (no customer contact data exists in these responses).
/// The runtime on/off switch of Leisure lives in the shared Features screen.
class LeisureAdminScreen extends StatefulWidget {
  const LeisureAdminScreen({required this.auth, this.product, super.key});

  final AuthRepository auth;

  /// `EVENTS` or `LEISURE`: the two products share one engine and one grant, but each has its own Control Center view
  /// (analytics, events, orders and categories are filtered by the server). Null shows both.
  final String? product;

  bool get isEvents => product == 'EVENTS';

  @override
  State<LeisureAdminScreen> createState() => _LeisureAdminScreenState();
}

class _LeisureAdminScreenState extends State<LeisureAdminScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 6, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    return Scaffold(
      appBar: AppBar(
        title: widget.isEvents
            ? Text(s.t('События: центр управления',
                'Іс-шаралар: басқару орталығы', 'Events control center'))
            : Text(s.t('Досуг: центр управления', 'Демалыс: басқару орталығы',
                'Leisure control center')),
        bottom: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: s.t('Обзор', 'Шолу', 'Overview')),
              Tab(text: s.t('Модерация', 'Модерация', 'Moderation')),
              Tab(text: s.t('Брони', 'Брондар', 'Bookings')),
              Tab(text: s.t('Жалобы', 'Шағымдар', 'Complaints')),
              Tab(text: s.t('Категории', 'Санаттар', 'Categories')),
              Tab(text: s.t('Журнал', 'Журнал', 'Audit')),
            ]),
      ),
      body: TabBarView(
          controller: _tabs,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _Overview(auth: widget.auth, product: widget.product),
            _Moderation(auth: widget.auth, product: widget.product),
            _Bookings(auth: widget.auth, product: widget.product),
            _Complaints(auth: widget.auth, product: widget.product),
            _Categories(auth: widget.auth, product: widget.product),
            _Audit(auth: widget.auth),
          ]),
    );
  }
}

const _root = 'admin/leisure';

Future<List<Map<String, dynamic>>> _list(AuthRepository auth, String path,
        [String? product]) async =>
    (await auth.authorizedJson('GET', '$_root/${_withProduct(path, product)}')
            as List)
        .cast<Map<String, dynamic>>();

String _withProduct(String path, String? product) => product == null
    ? path
    : '$path${path.contains('?') ? '&' : '?'}product=$product';

String _when(String iso) {
  final m = RegExp(r'^\d{4}-(\d{2})-(\d{2})T(\d{2}):(\d{2})').firstMatch(iso);
  return m == null ? iso : '${m[2]}.${m[1]} ${m[3]}:${m[4]}';
}

class _Failed extends StatelessWidget {
  const _Failed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(s.t('Не удалось загрузить данные',
              'Деректерді жүктеу мүмкін болмады', 'Could not load data')),
          const SizedBox(height: 12),
          FilledButton(
              onPressed: onRetry,
              child: Text(s.t('Повторить', 'Қайталау', 'Retry'))),
        ]),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

Future<String?> _askReason(BuildContext context, String title,
    {bool required = true}) async {
  final s = RideStrings(context);
  final c = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
          controller: c,
          maxLength: 200,
          decoration:
              InputDecoration(labelText: s.t('Причина', 'Себебі', 'Reason'))),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.t('Отмена', 'Болдырмау', 'Cancel'))),
        FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.t('Подтвердить', 'Растау', 'Confirm'))),
      ],
    ),
  );
  final text = c.text.trim();
  c.dispose();
  if (ok != true || (required && text.isEmpty)) return null;
  return text;
}

void _toast(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

class _Overview extends StatefulWidget {
  const _Overview({required this.auth, this.product});

  final AuthRepository auth;
  final String? product;

  @override
  State<_Overview> createState() => _OverviewState();
}

class _OverviewState extends State<_Overview> {
  int _days = 14;
  late Future<Map<String, dynamic>> _data = _load();

  Future<Map<String, dynamic>> _load() async =>
      await widget.auth.authorizedJson('GET',
              '$_root/${_withProduct('summary?days=$_days', widget.product)}')
          as Map<String, dynamic>;

  void _reload() => setState(() {
        _data = _load();
      });

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    final theme = Theme.of(context);
    return FutureBuilder<Map<String, dynamic>>(
      future: _data,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _Loading();
        }
        if (snap.hasError) return _Failed(onRetry: _reload);
        final d = snap.data!;
        Widget tile(String label, String value, {IconData? icon}) => Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (icon != null)
                        Icon(icon, color: theme.colorScheme.primary),
                      const SizedBox(height: 6),
                      FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(value,
                              style: theme.textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w900))),
                      Text(label, style: theme.textTheme.bodySmall),
                    ]),
              ),
            );
        Widget pair(Widget a, Widget b) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: IntrinsicHeight(
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                    Expanded(child: a),
                    const SizedBox(width: 12),
                    Expanded(child: b)
                  ])),
            );
        final perDay = (d['perDay'] as List).cast<Map<String, dynamic>>();
        return RefreshIndicator(
          onRefresh: () async {
            _reload();
            await _data;
          },
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Wrap(spacing: 8, children: [
              for (final n in [7, 14, 30])
                ChoiceChip(
                    label: Text(s.t('$n дн.', '$n күн', '$n d')),
                    selected: _days == n,
                    onSelected: (_) {
                      _days = n;
                      _reload();
                    }),
            ]),
            const SizedBox(height: 12),
            pair(
                tile(s.t('Мероприятия', 'Іс-шаралар', 'Events'),
                    '${d['events']}', icon: Icons.event_available_outlined),
                tile(s.t('Бронирования', 'Брондаулар', 'Bookings'),
                    '${d['orders']}',
                    icon: Icons.confirmation_number_outlined)),
            pair(
                tile(s.t('Сумма броней', 'Брон сомасы', 'Booked'),
                    formatTenge((d['bookedMinor'] as num).toInt()),
                    icon: Icons.payments_outlined),
                tile(s.t('Партнёры', 'Серіктестер', 'Partners'),
                    '${d['partners']}',
                    icon: Icons.storefront_outlined)),
            pair(
                tile(s.t('Возвраты', 'Қайтарулар', 'Refunded'),
                    formatTenge((d['refundedMinor'] as num).toInt()),
                    icon: Icons.undo_rounded),
                tile(s.t('Вошло гостей', 'Кірген қонақ', 'Guests admitted'),
                    '${d['admittedGuests']}',
                    icon: Icons.groups_outlined)),
            pair(
                tile(
                    s.t('Ждут проверки: площадки', 'Тексеруді күтуде: алаңдар',
                        'Venues in review'),
                    '${d['pendingVenues']}',
                    icon: Icons.pending_actions_outlined),
                tile(
                    s.t('Ждут проверки: события',
                        'Тексеруді күтуде: іс-шаралар', 'Events in review'),
                    '${d['pendingEvents']}',
                    icon: Icons.rule_rounded)),
            tile(s.t('Открытые жалобы', 'Ашық шағымдар', 'Open complaints'),
                '${d['openComplaints']}',
                icon: Icons.report_outlined),
            const SizedBox(height: 16),
            Text(
                s.t('Бронирования по дням', 'Күндер бойынша брондар',
                    'Bookings per day'),
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Semantics(
              label: s.t('График броней по дням', 'Күндер бойынша брон графигі',
                  'Bookings per day chart'),
              child: SizedBox(
                  height: 160,
                  child: CustomPaint(
                      painter: _LinePainter([
                        for (final p in perDay) (p['orders'] as num).toDouble()
                      ], theme.colorScheme.primary),
                      size: Size.infinite)),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(
                  perDay.isEmpty
                      ? ''
                      : _when('${perDay.first['day']}T00:00').split(' ').first,
                  style: theme.textTheme.bodySmall),
              Text(
                  perDay.isEmpty
                      ? ''
                      : _when('${perDay.last['day']}T00:00').split(' ').first,
                  style: theme.textTheme.bodySmall),
            ]),
          ]),
        );
      },
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.values, this.color);

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxV = math.max(1.0, values.reduce(math.max));
    final dx = values.length == 1 ? 0.0 : size.width / (values.length - 1);
    final path = Path();
    final area = Path()..moveTo(0, size.height);
    for (var i = 0; i < values.length; i++) {
      final p = Offset(
          dx * i, size.height - (values[i] / maxV) * (size.height - 8) - 4);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
      area.lineTo(p.dx, p.dy);
    }
    area.lineTo(dx * (values.length - 1), size.height);
    canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                color.withValues(alpha: .28),
                color.withValues(alpha: 0)
              ]).createShader(Offset.zero & size));
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) =>
      old.values != values || old.color != color;
}

class _Moderation extends StatefulWidget {
  const _Moderation({required this.auth, this.product});

  final AuthRepository auth;
  final String? product;

  @override
  State<_Moderation> createState() => _ModerationState();
}

class _ModerationState extends State<_Moderation> {
  bool _venues = true;
  String? _status = 'PENDING';
  late Future<List<Map<String, dynamic>>> _rows = _load();
  bool _busy = false;

  Future<List<Map<String, dynamic>>> _load() => _list(
      widget.auth,
      '${_venues ? 'venues' : 'events'}${_status == null ? '' : '?status=$_status'}',
      _venues ? null : widget.product);

  void _reload() => setState(() {
        _rows = _load();
      });

  Future<void> _decide(Map<String, dynamic> row, String decision) async {
    final s = RideStrings(context);
    String? reason;
    if (decision == 'REJECT' || decision == 'BLOCK') {
      reason = await _askReason(
          context,
          decision == 'REJECT'
              ? s.t('Отклонить', 'Қабылдамау', 'Reject')
              : s.t('Заблокировать', 'Бұғаттау', 'Block'));
      if (reason == null) return;
    }
    setState(() => _busy = true);
    try {
      await widget.auth.authorizedJson('POST',
          '$_root/${_venues ? 'venues' : 'events'}/${row['id']}/decision',
          body: {'decision': decision, if (reason != null) 'reason': reason});
      if (mounted) _reload();
    } catch (_) {
      if (mounted) {
        _toast(
            context,
            s.t('Не удалось выполнить действие',
                'Әрекетті орындау мүмкін болмады', 'The action failed'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    final theme = Theme.of(context);
    final statuses = _venues
        ? ['PENDING', 'APPROVED', 'REJECTED', 'BLOCKED']
        : ['PENDING', 'PUBLISHED', 'REJECTED', 'BLOCKED', 'ARCHIVED'];
    String label(String st) => switch (st) {
          'PENDING' => s.t('На проверке', 'Тексеруде', 'In review'),
          'APPROVED' ||
          'PUBLISHED' =>
            s.t('Одобрено', 'Мақұлданды', 'Approved'),
          'REJECTED' => s.t('Отклонено', 'Қабылданбады', 'Rejected'),
          'BLOCKED' => s.t('Заблокировано', 'Бұғатталды', 'Blocked'),
          'ARCHIVED' => s.t('Архив', 'Мұрағат', 'Archived'),
          _ => st,
        };
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
                value: true, label: Text(s.t('Площадки', 'Алаңдар', 'Venues'))),
            ButtonSegment(
                value: false,
                label: Text(s.t('Мероприятия', 'Іс-шаралар', 'Events')))
          ],
          selected: {_venues},
          onSelectionChanged: (v) {
            _venues = v.first;
            _status = 'PENDING';
            _reload();
          },
        ),
      ),
      SizedBox(
        height: 48,
        child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final st in [null, ...statuses])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                      label: Text(st == null
                          ? s.t('Все', 'Барлығы', 'All')
                          : label(st)),
                      selected: _status == st,
                      onSelected: (_) {
                        _status = st;
                        _reload();
                      }),
                ),
            ]),
      ),
      Expanded(
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _rows,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const _Loading();
            }
            if (snap.hasError) return _Failed(onRetry: _reload);
            final rows = snap.data!;
            if (rows.isEmpty) {
              return Center(child: Text(s.t('Пусто', 'Бос', 'Nothing here')));
            }
            return RefreshIndicator(
              onRefresh: () async {
                _reload();
                await _rows;
              },
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: rows.length,
                itemBuilder: (_, i) {
                  final r = rows[i];
                  final st = '${r['status']}';
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Expanded(
                                  child: Text(
                                      '${_venues ? r['name'] : r['title']}',
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                              fontWeight: FontWeight.w800))),
                              Text(label(st),
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: st == 'BLOCKED' || st == 'REJECTED'
                                          ? theme.colorScheme.error
                                          : theme.colorScheme.primary)),
                            ]),
                            Text(
                                _venues
                                    ? '${r['partner']} · ${r['district']} · ${r['events']}'
                                    : '${r['venue']} · ${r['category']} · ${r['bookingType']}',
                                style: theme.textTheme.bodySmall),
                            if (r['synthetic'] == true)
                              Text(
                                  s.t('синтетика (DEV)', 'синтетика (DEV)',
                                      'synthetic (DEV)'),
                                  style: theme.textTheme.bodySmall),
                            if (r['moderationNote'] != null)
                              Text('${r['moderationNote']}',
                                  style: theme.textTheme.bodySmall),
                            const SizedBox(height: 8),
                            Wrap(spacing: 8, runSpacing: 4, children: [
                              if (st == 'PENDING')
                                FilledButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _decide(r, 'APPROVE'),
                                    child: Text(s.t(
                                        'Одобрить', 'Мақұлдау', 'Approve'))),
                              if (st == 'PENDING')
                                OutlinedButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _decide(r, 'REJECT'),
                                    child: Text(s.t(
                                        'Отклонить', 'Қабылдамау', 'Reject'))),
                              if (st != 'BLOCKED')
                                OutlinedButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _decide(r, 'BLOCK'),
                                    child: Text(s.t(
                                        'Заблокировать', 'Бұғаттау', 'Block'))),
                              if (st == 'BLOCKED')
                                OutlinedButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _decide(r, 'UNBLOCK'),
                                    child: Text(s.t('Разблокировать',
                                        'Бұғаттан шығару', 'Unblock'))),
                            ]),
                          ]),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    ]);
  }
}

class _Bookings extends StatefulWidget {
  const _Bookings({required this.auth, this.product});

  final AuthRepository auth;
  final String? product;

  @override
  State<_Bookings> createState() => _BookingsState();
}

class _BookingsState extends State<_Bookings> {
  String? _status;
  late Future<List<Map<String, dynamic>>> _rows = _load();
  bool _busy = false;

  Future<List<Map<String, dynamic>>> _load() => _list(widget.auth,
      'orders${_status == null ? '' : '?status=$_status'}', widget.product);

  void _reload() => setState(() {
        _rows = _load();
      });

  Future<void> _cancel(Map<String, dynamic> o) async {
    final s = RideStrings(context);
    final reason = await _askReason(
        context, s.t('Отменить бронь', 'Броньнан бас тарту', 'Cancel booking'));
    if (reason == null) return;
    await _do(() => widget.auth.authorizedJson(
        'POST', '$_root/orders/${o['id']}/cancel',
        body: {'reason': reason}, expected: {204}));
  }

  Future<void> _refund(Map<String, dynamic> o) async {
    final s = RideStrings(context);
    final amount = TextEditingController();
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.t('Возврат (тест)', 'Қайтару (тест)', 'Refund (test)')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: amount,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                  labelText: s.t('Сумма, ₸', 'Сома, ₸', 'Amount, ₸'))),
          TextField(
              controller: reason,
              maxLength: 200,
              decoration: InputDecoration(
                  labelText: s.t('Причина', 'Себебі', 'Reason'))),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.t('Отмена', 'Болдырмау', 'Cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(s.t('Вернуть', 'Қайтару', 'Refund'))),
        ],
      ),
    );
    final tenge = int.tryParse(amount.text.trim());
    final why = reason.text.trim();
    amount.dispose();
    reason.dispose();
    if (ok != true || tenge == null || tenge <= 0 || why.isEmpty) return;
    await _do(() => widget.auth.authorizedJson(
        'POST', '$_root/payments/${o['paymentId']}/refund',
        body: {'amountMinor': tenge * 100, 'reason': why}));
  }

  Future<void> _do(Future<Object?> Function() action) async {
    final s = RideStrings(context);
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) _reload();
    } catch (_) {
      if (mounted) {
        _toast(
            context,
            s.t('Не удалось выполнить действие',
                'Әрекетті орындау мүмкін болмады', 'The action failed'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _tickets(Map<String, dynamic> o) async {
    final s = RideStrings(context);
    final rows = await _list(widget.auth, 'tickets?orderId=${o['id']}')
        .catchError((_) => <Map<String, dynamic>>[]);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Text(s.t('Билеты', 'Билеттер', 'Tickets'),
                  style: Theme.of(context).textTheme.titleLarge),
              for (final t in rows)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.confirmation_number_outlined),
                  title: Text('${t['id']}'.substring(0, 8).toUpperCase() +
                      (t['seat'] != null ? ' · ${t['seat']}' : '')),
                  subtitle: Text(
                      '${t['status']}${t['usedAt'] != null ? ' · ${_when('${t['usedAt']}')}' : ''}'),
                ),
            ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    final theme = Theme.of(context);
    return Column(children: [
      SizedBox(
        height: 56,
        child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            children: [
              for (final st in [null, 'PENDING', 'CONFIRMED', 'CANCELLED'])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                      label: Text(st ?? s.t('Все', 'Барлығы', 'All')),
                      selected: _status == st,
                      onSelected: (_) {
                        _status = st;
                        _reload();
                      }),
                ),
            ]),
      ),
      Expanded(
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _rows,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const _Loading();
            }
            if (snap.hasError) return _Failed(onRetry: _reload);
            final rows = snap.data!;
            if (rows.isEmpty) {
              return Center(child: Text(s.t('Пусто', 'Бос', 'Nothing here')));
            }
            return RefreshIndicator(
              onRefresh: () async {
                _reload();
                await _rows;
              },
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: rows.length,
                itemBuilder: (_, i) {
                  final o = rows[i];
                  final st = '${o['status']}';
                  final ps = o['paymentStatus'] as String?;
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Expanded(
                                  child: Text('${o['event']}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                              fontWeight: FontWeight.w800))),
                              Text(st,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: st == 'CANCELLED'
                                          ? theme.colorScheme.error
                                          : theme.colorScheme.primary)),
                            ]),
                            Text(
                                '${o['venue']} · ${_when('${o['startsAt']}')} · ${s.t('гостей', 'қонақ', 'guests')}: ${o['guests']}',
                                style: theme.textTheme.bodySmall),
                            Text(
                                '${formatTenge((o['totalMinor'] as num).toInt())} · ${o['paymentMethod']}${ps != null ? ' · $ps' : ''}',
                                style: theme.textTheme.bodySmall),
                            Wrap(spacing: 8, children: [
                              TextButton(
                                  onPressed: () => _tickets(o),
                                  child: Text(
                                      s.t('Билеты', 'Билеттер', 'Tickets'))),
                              if (st != 'CANCELLED')
                                TextButton(
                                    onPressed: _busy ? null : () => _cancel(o),
                                    child: Text(s.t(
                                        'Отменить', 'Бас тарту', 'Cancel'))),
                              if (ps == 'TEST_CAPTURED' ||
                                  ps == 'TEST_PART_REFUNDED')
                                TextButton(
                                    onPressed: _busy ? null : () => _refund(o),
                                    child: Text(
                                        s.t('Возврат', 'Қайтару', 'Refund'))),
                            ]),
                          ]),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    ]);
  }
}

class _Complaints extends StatefulWidget {
  const _Complaints({required this.auth, this.product});

  final AuthRepository auth;
  final String? product;

  @override
  State<_Complaints> createState() => _ComplaintsState();
}

class _ComplaintsState extends State<_Complaints> {
  bool _all = false;
  late Future<List<Map<String, dynamic>>> _rows = _load();

  Future<List<Map<String, dynamic>>> _load() =>
      _list(widget.auth, 'complaints?includeResolved=$_all', widget.product);

  void _reload() => setState(() {
        _rows = _load();
      });

  Future<void> _resolve(Map<String, dynamic> c) async {
    final s = RideStrings(context);
    final text =
        await _askReason(context, s.t('Решение', 'Шешім', 'Resolution'));
    if (text == null) return;
    try {
      await widget.auth.authorizedJson(
          'POST', '$_root/complaints/${c['id']}/resolve',
          body: {'resolution': text}, expected: {204});
      if (mounted) _reload();
    } catch (_) {
      if (mounted) {
        _toast(
            context,
            s.t('Не удалось выполнить действие',
                'Әрекетті орындау мүмкін болмады', 'The action failed'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    final theme = Theme.of(context);
    return Column(children: [
      SwitchListTile(
          title: Text(s.t('Показать решённые', 'Шешілгендерді көрсету',
              'Include resolved')),
          value: _all,
          onChanged: (v) {
            _all = v;
            _reload();
          }),
      Expanded(
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _rows,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const _Loading();
            }
            if (snap.hasError) return _Failed(onRetry: _reload);
            final rows = snap.data!;
            if (rows.isEmpty) {
              return Center(
                  child: Text(s.t('Жалоб нет', 'Шағым жоқ', 'No complaints')));
            }
            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: rows.length,
              itemBuilder: (_, i) {
                final c = rows[i];
                return Card(
                  child: ListTile(
                    title: Text('${c['venue']}'),
                    subtitle: Text(
                        '${c['body']}${c['resolution'] != null ? '\n→ ${c['resolution']}' : ''}'),
                    isThreeLine: true,
                    trailing: c['status'] == 'OPEN'
                        ? FilledButton.tonal(
                            onPressed: () => _resolve(c),
                            child: Text(s.t('Решить', 'Шешу', 'Resolve')))
                        : Text('✓', style: theme.textTheme.titleLarge),
                  ),
                );
              },
            );
          },
        ),
      ),
    ]);
  }
}

class _Categories extends StatefulWidget {
  const _Categories({required this.auth, this.product});

  final AuthRepository auth;
  final String? product;

  @override
  State<_Categories> createState() => _CategoriesState();
}

class _CategoriesState extends State<_Categories> {
  late Future<List<Map<String, dynamic>>> _rows =
      _list(widget.auth, 'categories', widget.product);

  void _reload() => setState(() {
        _rows = _list(widget.auth, 'categories', widget.product);
      });

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _rows,
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _Loading();
        }
        if (snap.hasError) return _Failed(onRetry: _reload);
        return ListView(children: [
          for (final c in snap.data!)
            SwitchListTile(
              title: Text('${c['nameRu']}'),
              subtitle: Text('${c['bookingType']}'),
              value: c['enabled'] == true,
              onChanged: (v) async {
                try {
                  await widget.auth.authorizedJson(
                      'PATCH', '$_root/categories/${c['code']}',
                      body: {'enabled': v});
                  if (mounted) _reload();
                } catch (_) {
                  if (mounted) {
                    _toast(
                        this.context,
                        s.t(
                            'Не удалось выполнить действие',
                            'Әрекетті орындау мүмкін болмады',
                            'The action failed'));
                  }
                }
              },
            ),
        ]);
      },
    );
  }
}

class _Audit extends StatefulWidget {
  const _Audit({required this.auth});

  final AuthRepository auth;

  @override
  State<_Audit> createState() => _AuditState();
}

class _AuditState extends State<_Audit> {
  late Future<List<Map<String, dynamic>>> _rows =
      _list(widget.auth, 'audit?limit=100');

  void _reload() => setState(() {
        _rows = _list(widget.auth, 'audit?limit=100');
      });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _rows,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _Loading();
        }
        if (snap.hasError) return _Failed(onRetry: _reload);
        return RefreshIndicator(
          onRefresh: () async {
            _reload();
            await _rows;
          },
          child: ListView(children: [
            for (final a in snap.data!)
              ListTile(
                dense: true,
                leading: Icon(a['actorType'] == 'ADMIN'
                    ? Icons.admin_panel_settings_outlined
                    : a['actorType'] == 'EXECUTOR'
                        ? Icons.badge_outlined
                        : Icons.storefront_outlined),
                title: Text('${a['action']}'),
                subtitle: Text(
                    '${a['detail'] ?? ''}\n${_when('${a['at']}')} · ${a['target']}'),
                isThreeLine: true,
              ),
          ]),
        );
      },
    );
  }
}
