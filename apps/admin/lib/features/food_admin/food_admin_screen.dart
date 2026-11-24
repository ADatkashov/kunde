import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:kunde_models/food_models.dart' show formatTenge;
import 'package:kunde_auth/auth_repository.dart';
import 'package:kunde_ui/ride_strings.dart';

part 'groceries_admin_screen.dart';

/// Food Control Center for administrators. Everything goes through `/api/v1/admin/food/**`, where the FOOD_OPERATIONS grant is checked on
/// every request. The screen only presents what the server returns: with no orders every number is zero (never a sample value) and no
/// customer name, phone or address exists in these responses (orders carry a short customer reference only).
class FoodAdminScreen extends StatefulWidget {
  const FoodAdminScreen({required this.auth, super.key});

  final AuthRepository auth;

  @override
  State<FoodAdminScreen> createState() => _FoodAdminScreenState();
}

class _FoodAdminScreenState extends State<FoodAdminScreen>
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
        title: Text(s.t('Еда: центр управления', 'Тамақ: басқару орталығы',
            'Food control center')),
        bottom: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: s.t('Обзор', 'Шолу', 'Overview')),
              Tab(text: s.t('Заказы', 'Тапсырыстар', 'Orders')),
              Tab(text: s.t('Рестораны', 'Мейрамханалар', 'Restaurants')),
              Tab(text: s.t('Акции', 'Акциялар', 'Promotions')),
              Tab(text: s.t('Отзывы', 'Пікірлер', 'Reviews')),
              Tab(text: s.t('Журнал', 'Журнал', 'Audit')),
            ]),
      ),
      body: TabBarView(
          controller: _tabs,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _Overview(auth: widget.auth),
            _Orders(auth: widget.auth),
            _Restaurants(auth: widget.auth),
            _Promotions(auth: widget.auth),
            _Reviews(auth: widget.auth),
            _Audit(auth: widget.auth),
          ]),
    );
  }
}

const _root = 'admin/food';

Future<List<Map<String, dynamic>>> _list(AuthRepository auth, String path,
        [String root = _root]) async =>
    (await auth.authorizedJson('GET', '$root/$path') as List)
        .cast<Map<String, dynamic>>();

String _when(String iso) {
  final m = RegExp(r'^\d{4}-(\d{2})-(\d{2})T(\d{2}):(\d{2})').firstMatch(iso);
  return m == null ? iso : '${m[2]}.${m[1]} ${m[3]}:${m[4]}';
}

int _n(Object? v) => (v as num?)?.toInt() ?? 0;

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

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
      child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(text, textAlign: TextAlign.center)));
}

Future<String?> _askReason(BuildContext context, String title) async {
  final s = RideStrings(context);
  final c = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
          key: const Key('food-admin-reason'),
          controller: c,
          maxLength: 200,
          decoration: InputDecoration(
              labelText: s.t('Причина (от 3 символов)', 'Себебі (3 таңбадан)',
                  'Reason (3+ characters)'))),
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
  // The controller is not disposed here: the dialog is still animating out and would read a disposed controller.
  final text = c.text.trim();
  if (ok != true || text.length < 3) return null;
  return text;
}

void _toast(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

/// Runs an admin action and refreshes the list; a server refusal is shown instead of being hidden.
Future<void> _act(BuildContext context, Future<Object?> Function() call,
    VoidCallback reload) async {
  final s = RideStrings(context);
  try {
    await call();
    reload();
  } on Object {
    if (context.mounted) {
      _toast(
          context,
          s.t(
              'Действие не выполнено. Проверьте права и состояние.',
              'Әрекет орындалмады. Құқықтар мен күйді тексеріңіз.',
              'The action failed. Check permissions and state.'));
    }
  }
}

class _Overview extends StatefulWidget {
  const _Overview({required this.auth});

  final AuthRepository auth;

  @override
  State<_Overview> createState() => _OverviewState();
}

class _OverviewState extends State<_Overview> {
  int _days = 7;
  late Future<Map<String, dynamic>> _data = _load();

  Future<Map<String, dynamic>> _load() async =>
      await widget.auth.authorizedJson('GET', '$_root/summary?days=$_days')
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
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) return _Failed(onRetry: _reload);
        final d = snap.data!;
        Widget tile(String label, String value, IconData icon, {Key? key}) =>
            Card(
              key: key,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
        final statuses = (d['statuses'] as List).cast<Map<String, dynamic>>();
        final total = _n(d['orders']);
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
                tile(
                    s.t('Рестораны', 'Мейрамханалар', 'Restaurants'),
                    '${_n(d['openRestaurants'])} / ${_n(d['restaurants'])}',
                    Icons.storefront_outlined,
                    key: const Key('kpi-restaurants')),
                tile(s.t('Заказы', 'Тапсырыстар', 'Orders'), '$total',
                    Icons.receipt_long_outlined,
                    key: const Key('kpi-orders'))),
            pair(
                tile(s.t('Выручка', 'Түсім', 'Revenue'),
                    formatTenge(_n(d['revenueMinor'])), Icons.payments_outlined,
                    key: const Key('kpi-revenue')),
                tile(
                    s.t('Средний чек', 'Орташа чек', 'Average check'),
                    formatTenge(_n(d['averageCheckMinor'])),
                    Icons.shopping_bag_outlined,
                    key: const Key('kpi-average'))),
            pair(
                tile(s.t('Доставка', 'Жеткізу', 'Delivery'),
                    '${_n(d['deliveryOrders'])}', Icons.delivery_dining),
                tile(s.t('Самовывоз', 'Өзі алып кету', 'Pickup'),
                    '${_n(d['pickupOrders'])}', Icons.storefront_outlined)),
            pair(
                tile(
                    s.t('Проблемные заказы', 'Мәселелі тапсырыстар',
                        'Problem orders'),
                    '${_n(d['problemOrders'])}',
                    Icons.warning_amber_rounded),
                tile(s.t('Открытые жалобы', 'Ашық шағымдар', 'Open complaints'),
                    '${_n(d['openComplaints'])}', Icons.report_outlined)),
            if (total == 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                    s.t(
                        'За выбранный период заказов нет.',
                        'Таңдалған кезеңде тапсырыс жоқ.',
                        'No orders in the selected period.'),
                    key: const Key('food-admin-empty'),
                    style: theme.textTheme.bodyMedium),
              ),
            const SizedBox(height: 8),
            Text(
                s.t('Заказы по дням', 'Күндер бойынша тапсырыстар',
                    'Orders per day'),
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Semantics(
              label: s.t('График заказов по дням',
                  'Күндер бойынша тапсырыс графигі', 'Orders per day chart'),
              child: SizedBox(
                  height: 140,
                  child: CustomPaint(
                      painter: _LinePainter(
                          [for (final p in perDay) _n(p['orders']).toDouble()],
                          theme.colorScheme.primary),
                      size: Size.infinite)),
            ),
            const SizedBox(height: 16),
            Text(s.t('Статусы', 'Күйлер', 'Statuses'),
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            for (final st in statuses)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(_statusLabel(s, '${st['status']}')),
                trailing: Text('${_n(st['count'])}'),
              ),
          ]),
        );
      },
    );
  }
}

String _statusLabel(RideStrings s, String status) => switch (status) {
      'PLACED' => s.t('Новый', 'Жаңа', 'New'),
      'ACCEPTED' => s.t('Принят', 'Қабылданды', 'Accepted'),
      'PREPARING' => s.t('Готовится', 'Дайындалуда', 'Preparing'),
      'READY_FOR_PICKUP' => s.t('Готов', 'Дайын', 'Ready'),
      'ON_THE_WAY' => s.t('В пути', 'Жолда', 'On the way'),
      'DELIVERED' => s.t('Завершён', 'Аяқталды', 'Completed'),
      'CANCELLED' => s.t('Отменён', 'Бас тартылды', 'Cancelled'),
      _ => status,
    };

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
    for (var i = 0; i < values.length; i++) {
      final p = Offset(
          dx * i, size.height - (values[i] / maxV) * (size.height - 8) - 4);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.values != values || old.color != color;
}

/// A server-backed list with pull-to-refresh, loading, error and empty states.
class _ServerList extends StatefulWidget {
  const _ServerList({
    required this.auth,
    required this.path,
    required this.emptyText,
    required this.itemBuilder,
    this.root = _root,
  });

  final AuthRepository auth;
  final String root;
  final String path;
  final String emptyText;
  final Widget Function(BuildContext, Map<String, dynamic>, VoidCallback reload)
      itemBuilder;

  @override
  State<_ServerList> createState() => _ServerListState();
}

class _ServerListState extends State<_ServerList> {
  late Future<List<Map<String, dynamic>>> _data =
      _list(widget.auth, widget.path, widget.root);

  void _reload() => setState(() {
        _data = _list(widget.auth, widget.path, widget.root);
      });

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<List<Map<String, dynamic>>>(
        future: _data,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) return _Failed(onRetry: _reload);
          final rows = snap.data!;
          if (rows.isEmpty) return _Empty(widget.emptyText);
          return RefreshIndicator(
            onRefresh: () async {
              _reload();
              await _data;
            },
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) =>
                  widget.itemBuilder(context, rows[i], _reload),
            ),
          );
        },
      );
}

class _Orders extends StatelessWidget {
  const _Orders({required this.auth});

  final AuthRepository auth;

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    return _ServerList(
      auth: auth,
      path: 'orders',
      emptyText:
          s.t('Заказов пока нет.', 'Тапсырыс әлі жоқ.', 'No orders yet.'),
      itemBuilder: (context, o, reload) {
        final refundable = o['paymentMethod'] == 'TEST_CARD' &&
            o['paymentStatus'] == 'TEST_PAID' &&
            (o['status'] == 'DELIVERED' || o['status'] == 'CANCELLED');
        return Card(
          child: ListTile(
            title: Text(
                '${o['restaurant']} · ${formatTenge(_n(o['totalMinor']))}'),
            subtitle: Text('${_statusLabel(s, '${o['status']}')} · '
                '${o['fulfillmentType'] == 'PICKUP' ? s.t('самовывоз', 'өзі алып кету', 'pickup') : s.t('доставка', 'жеткізу', 'delivery')} · '
                '${o['paymentStatus']} · ${s.t('клиент', 'клиент', 'customer')} ${o['customerRef']}\n'
                '${_when('${o['placedAt']}')}'),
            isThreeLine: true,
            trailing: refundable
                ? TextButton(
                    key: const Key('food-admin-refund'),
                    onPressed: () async {
                      final reason = await _askReason(
                          context,
                          s.t('Тестовый возврат', 'Сынақ қайтару',
                              'Test refund'));
                      if (reason == null || !context.mounted) return;
                      await _act(
                          context,
                          () => auth.authorizedJson(
                              'POST', '$_root/orders/${o['id']}/refund',
                              body: {'reason': reason}),
                          reload);
                    },
                    child: Text(s.t('Возврат', 'Қайтару', 'Refund')))
                : null,
          ),
        );
      },
    );
  }
}

class _Restaurants extends StatelessWidget {
  const _Restaurants({required this.auth});

  final AuthRepository auth;

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    return _ServerList(
      auth: auth,
      path: 'restaurants',
      emptyText: s.t(
          'Ресторанов пока нет.', 'Мейрамхана әлі жоқ.', 'No restaurants yet.'),
      itemBuilder: (context, r, reload) {
        final blocked = r['moderationStatus'] == 'BLOCKED';
        return Card(
          child: ListTile(
            title: Text('${r['name']}'),
            subtitle: Text([
              if (r['partner'] != null) '${r['partner']}',
              blocked
                  ? s.t('Заблокирован', 'Бұғатталған', 'Blocked')
                  : (r['open'] == true
                      ? s.t('Открыт', 'Ашық', 'Open')
                      : s.t('Закрыт', 'Жабық', 'Closed')),
              if (r['ratingAvg'] != null)
                '★ ${r['ratingAvg']} (${_n(r['ratingCount'])})',
              '${s.t('заказов', 'тапсырыс', 'orders')}: ${_n(r['orders'])}',
              if (r['synthetic'] == true) s.t('демо', 'демо', 'demo'),
            ].join(' · ')),
            trailing: TextButton(
              onPressed: () async {
                final reason = await _askReason(
                    context,
                    blocked
                        ? s.t('Разблокировать ресторан', 'Мейрамхананы ашу',
                            'Unblock restaurant')
                        : s.t('Заблокировать ресторан', 'Мейрамхананы бұғаттау',
                            'Block restaurant'));
                if (reason == null || !context.mounted) return;
                await _act(
                    context,
                    () => auth.authorizedJson(
                            'POST', '$_root/restaurants/${r['id']}/moderation',
                            body: {
                              'decision': blocked ? 'UNBLOCK' : 'BLOCK',
                              'reason': reason
                            }),
                    reload);
              },
              child: Text(blocked
                  ? s.t('Разблок.', 'Ашу', 'Unblock')
                  : s.t('Блок', 'Бұғаттау', 'Block')),
            ),
          ),
        );
      },
    );
  }
}

class _Promotions extends StatelessWidget {
  const _Promotions({required this.auth});

  final AuthRepository auth;

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    return _ServerList(
      auth: auth,
      path: 'promotions',
      emptyText: s.t('Акций пока нет.', 'Акция әлі жоқ.', 'No promotions yet.'),
      itemBuilder: (context, p, reload) {
        final disabled = p['status'] == 'DISABLED';
        final value = p['kind'] == 'PERCENT'
            ? '${p['value']}%'
            : formatTenge(_n(p['value']));
        return Card(
          child: ListTile(
            title: Text('${p['title']} · $value'),
            subtitle: Text([
              if (p['code'] != null) '${p['code']}',
              '${p['status']}',
              if (p['restaurantName'] != null) '${p['restaurantName']}',
              '${_n(p['redeemed'])}${p['maxRedemptions'] == null ? '' : '/${p['maxRedemptions']}'}',
              if (p['partnerOwned'] == true)
                s.t('от партнёра', 'серіктестен', 'partner'),
            ].join(' · ')),
            trailing: TextButton(
              onPressed: () async {
                final reason = await _askReason(
                    context,
                    disabled
                        ? s.t('Включить акцию', 'Акцияны қосу',
                            'Enable promotion')
                        : s.t('Отключить акцию', 'Акцияны өшіру',
                            'Disable promotion'));
                if (reason == null || !context.mounted) return;
                await _act(
                    context,
                    () => auth.authorizedJson(
                            'POST', '$_root/promotions/${p['id']}/status',
                            body: {
                              'status': disabled ? 'ACTIVE' : 'DISABLED',
                              'reason': reason
                            }),
                    reload);
              },
              child: Text(disabled
                  ? s.t('Включить', 'Қосу', 'Enable')
                  : s.t('Отключить', 'Өшіру', 'Disable')),
            ),
          ),
        );
      },
    );
  }
}

class _Reviews extends StatelessWidget {
  const _Reviews({required this.auth});

  final AuthRepository auth;

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    return _ServerList(
      auth: auth,
      path: 'reviews',
      emptyText: s.t('Отзывов пока нет.', 'Пікір әлі жоқ.', 'No reviews yet.'),
      itemBuilder: (context, r, reload) {
        final hidden = r['status'] == 'HIDDEN';
        return Card(
          child: ListTile(
            title: Text('${'★' * _n(r['rating'])} · ${r['restaurant']}'),
            subtitle: Text([
              if (r['comment'] != null) '${r['comment']}',
              if (_n(r['complaints']) > 0)
                '${s.t('жалоб', 'шағым', 'complaints')}: ${_n(r['complaints'])}',
              if (hidden) s.t('скрыт', 'жасырылған', 'hidden'),
            ].join('\n')),
            trailing: TextButton(
              onPressed: () async {
                final reason = await _askReason(
                    context,
                    hidden
                        ? s.t(
                            'Показать отзыв', 'Пікірді көрсету', 'Show review')
                        : s.t('Скрыть отзыв', 'Пікірді жасыру', 'Hide review'));
                if (reason == null || !context.mounted) return;
                await _act(
                    context,
                    () => auth.authorizedJson(
                            'POST', '$_root/reviews/${r['id']}/moderation',
                            body: {
                              'decision': hidden ? 'SHOW' : 'HIDE',
                              'reason': reason
                            }),
                    reload);
              },
              child: Text(hidden
                  ? s.t('Показать', 'Көрсету', 'Show')
                  : s.t('Скрыть', 'Жасыру', 'Hide')),
            ),
          ),
        );
      },
    );
  }
}

class _Audit extends StatelessWidget {
  const _Audit({required this.auth});

  final AuthRepository auth;

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    return _ServerList(
      auth: auth,
      path: 'audit',
      emptyText: s.t('Записей пока нет.', 'Жазба әлі жоқ.', 'No entries yet.'),
      itemBuilder: (context, a, reload) => Card(
        child: ListTile(
          dense: true,
          title: Text('${a['action']} · ${a['actorType']}'),
          subtitle: Text(
              '${a['target']}${'${a['detail']}'.isEmpty ? '' : '\n${a['detail']}'}\n${_when('${a['at']}')}'),
          isThreeLine: true,
        ),
      ),
    );
  }
}
