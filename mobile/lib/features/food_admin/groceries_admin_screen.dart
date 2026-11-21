part of 'food_admin_screen.dart';

const _groceriesRoot = 'admin/groceries';

/// Groceries Control Center. Everything goes through `/api/v1/admin/groceries/**`, scoped by the GROCERIES_OPERATIONS grant: it shows
/// only Groceries stores, orders, promotions and reviews. With no orders every number is zero (never a sample value) and no customer
/// name, phone or address exists in these responses.
class GroceriesAdminScreen extends StatefulWidget {
  const GroceriesAdminScreen({required this.auth, super.key});

  final AuthRepository auth;

  @override
  State<GroceriesAdminScreen> createState() => _GroceriesAdminScreenState();
}

class _GroceriesAdminScreenState extends State<GroceriesAdminScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 8, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    final auth = widget.auth;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('Продукты: центр управления',
            'Азық-түлік: басқару орталығы', 'Groceries control center')),
        bottom: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: s.t('Обзор', 'Шолу', 'Overview')),
              Tab(text: s.t('Заказы', 'Тапсырыстар', 'Orders')),
              Tab(text: s.t('Магазины', 'Дүкендер', 'Stores')),
              Tab(
                  text: s.t('Каталог и склад', 'Каталог және қойма',
                      'Catalog & stock')),
              Tab(text: s.t('Акции', 'Акциялар', 'Promotions')),
              Tab(text: s.t('Отзывы', 'Пікірлер', 'Reviews')),
              Tab(text: s.t('Жалобы', 'Шағымдар', 'Complaints')),
              Tab(text: s.t('Журнал', 'Журнал', 'Audit')),
            ]),
      ),
      body: TabBarView(
          controller: _tabs,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _GroceriesOverview(auth: auth),
            _GroceriesOrders(auth: auth),
            _GroceriesStores(auth: auth),
            _GroceriesProblems(auth: auth),
            _GroceriesPromotions(auth: auth),
            _GroceriesReviews(auth: auth),
            _GroceriesComplaints(auth: auth),
            _GroceriesAudit(auth: auth),
          ]),
    );
  }
}

String _categoryName(RideStrings s, String slug) => switch (slug) {
      'fruit_veg' =>
        s.t('Овощи и фрукты', 'Көкөніс және жеміс', 'Fruit & vegetables'),
      'dairy' => s.t('Молочные продукты', 'Сүт өнімдері', 'Dairy'),
      'meat' => s.t('Мясо и птица', 'Ет және құс еті', 'Meat & poultry'),
      'fish' => s.t(
          'Рыба и морепродукты', 'Балық және теңіз өнімдері', 'Fish & seafood'),
      'bakery' => s.t('Хлеб и выпечка', 'Нан және тоқаш', 'Bread & bakery'),
      'drinks' => s.t('Напитки', 'Сусындар', 'Drinks'),
      'pantry' => s.t('Бакалея', 'Бакалея', 'Pantry'),
      'sweets' => s.t('Сладости', 'Тәттілер', 'Sweets & snacks'),
      'frozen' => s.t('Замороженные продукты', 'Мұздатылған өнімдер', 'Frozen'),
      'ready_meals' => s.t('Готовая еда', 'Дайын тағам', 'Ready meals'),
      'household' =>
        s.t('Бытовая химия и дом', 'Тұрмыстық химия және үй', 'Household'),
      'kids' => s.t('Детские товары', 'Балалар тауарлары', 'Kids'),
      _ => s.t('Без категории', 'Санатсыз', 'Uncategorized'),
    };

class _GroceriesOverview extends StatefulWidget {
  const _GroceriesOverview({required this.auth});

  final AuthRepository auth;

  @override
  State<_GroceriesOverview> createState() => _GroceriesOverviewState();
}

class _GroceriesOverviewState extends State<_GroceriesOverview> {
  int _days = 7;
  late Future<Map<String, dynamic>> _data = _load();

  Future<Map<String, dynamic>> _load() async => await widget.auth
          .authorizedJson('GET', '$_groceriesRoot/summary?days=$_days')
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
        final categories =
            (d['categories'] as List).cast<Map<String, dynamic>>();
        final total = _n(d['orders']);
        final maxRevenue = categories.fold<int>(
            1, (m, c) => math.max(m, _n(c['revenueMinor'])));
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
                    s.t('Магазины', 'Дүкендер', 'Stores'),
                    '${_n(d['openStores'])} / ${_n(d['stores'])}',
                    Icons.storefront_outlined,
                    key: const Key('kpi-stores')),
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
                    s.t('Заказы с заменами', 'Ауыстырылған тапсырыстар',
                        'Orders with changes'),
                    '${_n(d['changedOrders'])}',
                    Icons.swap_horiz_rounded),
                tile(
                    s.t('Проблемные заказы', 'Мәселелі тапсырыстар',
                        'Problem orders'),
                    '${_n(d['problemOrders'])}',
                    Icons.warning_amber_rounded)),
            pair(
                tile(s.t('Мало на складе', 'Қоймада аз', 'Low stock'),
                    '${_n(d['lowStockProducts'])}', Icons.inventory_2_outlined,
                    key: const Key('kpi-low-stock')),
                tile(
                    s.t('Нет в наличии', 'Қолда жоқ', 'Out of stock'),
                    '${_n(d['outOfStockProducts'])}',
                    Icons.remove_shopping_cart_outlined)),
            pair(
                tile(
                    s.t('Заказы ждут курьера', 'Курьерді күтетін тапсырыстар',
                        'Waiting for a courier'),
                    '${_n(d['openCourierTasks'])}',
                    Icons.hourglass_top_outlined),
                tile(
                    s.t('Курьеры в пути', 'Жолдағы курьерлер',
                        'Couriers on the way'),
                    '${_n(d['activeCourierTasks'])}',
                    Icons.two_wheeler_outlined)),
            pair(
                tile(s.t('Открытые жалобы', 'Ашық шағымдар', 'Open complaints'),
                    '${_n(d['openComplaints'])}', Icons.report_outlined),
                tile(s.t('Возвраты', 'Қайтарулар', 'Refunded'),
                    formatTenge(_n(d['refundedMinor'])), Icons.undo_outlined)),
            if (total == 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                    s.t(
                        'За выбранный период заказов нет.',
                        'Таңдалған кезеңде тапсырыс жоқ.',
                        'No orders in the selected period.'),
                    key: const Key('groceries-admin-empty')),
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
            Text(
                s.t('Категории товаров (выручка)', 'Тауар санаттары (түсім)',
                    'Product categories (revenue)'),
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            if (categories.isEmpty)
              Text(
                  s.t(
                      'Продаж по категориям пока нет.',
                      'Санат бойынша сатылым әлі жоқ.',
                      'No category sales yet.'),
                  key: const Key('groceries-admin-no-categories')),
            for (final c in categories)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Semantics(
                  label:
                      '${_categoryName(s, '${c['category']}')} ${formatTenge(_n(c['revenueMinor']))}',
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                              child:
                                  Text(_categoryName(s, '${c['category']}'))),
                          Text(formatTenge(_n(c['revenueMinor'])),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                        ]),
                        const SizedBox(height: 3),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                              value: _n(c['revenueMinor']) / maxRevenue,
                              minHeight: 8),
                        ),
                      ]),
                ),
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

class _GroceriesOrders extends StatelessWidget {
  const _GroceriesOrders({required this.auth});

  final AuthRepository auth;

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    return _ServerList(
      auth: auth,
      root: _groceriesRoot,
      path: 'orders',
      emptyText:
          s.t('Заказов пока нет.', 'Тапсырыс әлі жоқ.', 'No orders yet.'),
      itemBuilder: (context, o, reload) {
        final refundable = o['paymentMethod'] == 'TEST_CARD' &&
            o['paymentStatus'] == 'TEST_PAID' &&
            (o['status'] == 'DELIVERED' || o['status'] == 'CANCELLED');
        return Card(
          child: ListTile(
            title: Text('${o['store']} · ${formatTenge(_n(o['totalMinor']))}'),
            subtitle: Text('${_statusLabel(s, '${o['status']}')} · '
                '${o['fulfillmentType'] == 'PICKUP' ? s.t('самовывоз', 'өзі алып кету', 'pickup') : s.t('доставка', 'жеткізу', 'delivery')} · '
                '${o['paymentStatus']}${o['hasChanges'] == true ? ' · ${s.t('замены', 'ауыстыру', 'changes')}' : ''}\n'
                '${s.t('клиент', 'клиент', 'customer')} ${o['customerRef']} · ${_when('${o['placedAt']}')}'),
            isThreeLine: true,
            trailing: refundable
                ? TextButton(
                    key: const Key('groceries-admin-refund'),
                    onPressed: () async {
                      final reason = await _askReason(
                          context,
                          s.t('Тестовый возврат', 'Сынақ қайтару',
                              'Test refund'));
                      if (reason == null || !context.mounted) return;
                      await _act(
                          context,
                          () => auth.authorizedJson('POST',
                              '$_groceriesRoot/orders/${o['id']}/refund',
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

class _GroceriesStores extends StatelessWidget {
  const _GroceriesStores({required this.auth});

  final AuthRepository auth;

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    return _ServerList(
      auth: auth,
      root: _groceriesRoot,
      path: 'stores',
      emptyText: s.t('Магазинов пока нет.', 'Дүкен әлі жоқ.', 'No stores yet.'),
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
              '${s.t('товаров', 'тауар', 'products')}: ${_n(r['products'])}',
              '${s.t('заказов', 'тапсырыс', 'orders')}: ${_n(r['orders'])}',
              if (r['synthetic'] == true) s.t('демо', 'демо', 'demo'),
            ].join(' · ')),
            trailing: TextButton(
              onPressed: () async {
                final reason = await _askReason(
                    context,
                    blocked
                        ? s.t('Разблокировать магазин', 'Дүкенді ашу',
                            'Unblock store')
                        : s.t('Заблокировать магазин', 'Дүкенді бұғаттау',
                            'Block store'));
                if (reason == null || !context.mounted) return;
                await _act(
                    context,
                    () => auth.authorizedJson('POST',
                            '$_groceriesRoot/stores/${r['id']}/moderation',
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

class _GroceriesProblems extends StatelessWidget {
  const _GroceriesProblems({required this.auth});

  final AuthRepository auth;

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    return _ServerList(
      auth: auth,
      root: _groceriesRoot,
      path: 'catalog/problems',
      emptyText: s.t('Проблем с каталогом и складом нет.',
          'Каталог пен қоймада мәселе жоқ.', 'No catalog or stock problems.'),
      itemBuilder: (context, p, reload) {
        final problem = switch ('${p['problem']}') {
          'OUT_OF_STOCK' => s.t('Нет в наличии', 'Қолда жоқ', 'Out of stock'),
          'LOW_STOCK' => s.t('Мало на складе', 'Қоймада аз', 'Low stock'),
          'UNAVAILABLE' => s.t('Отключён', 'Өшірулі', 'Disabled'),
          _ => s.t('Без категории', 'Санатсыз', 'No category'),
        };
        final unit =
            p['unit'] == 'KG' ? s.t('г', 'г', 'g') : s.t('шт', 'дана', 'pcs');
        return Card(
          child: ListTile(
            title: Text('${p['name']}'),
            subtitle: Text(
                '${p['store']} · ${_categoryName(s, '${p['category']}')}'
                '${p['stockQty'] == null ? '' : ' · ${p['stockQty']} $unit'}'),
            trailing: Text(problem,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w700)),
          ),
        );
      },
    );
  }
}

class _GroceriesPromotions extends StatelessWidget {
  const _GroceriesPromotions({required this.auth});

  final AuthRepository auth;

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    return _ServerList(
      auth: auth,
      root: _groceriesRoot,
      path: 'promotions',
      emptyText: s.t('Акций магазинов пока нет.', 'Дүкен акциясы әлі жоқ.',
          'No store promotions yet.'),
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
                    () => auth.authorizedJson('POST',
                            '$_groceriesRoot/promotions/${p['id']}/status',
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

class _GroceriesReviews extends StatelessWidget {
  const _GroceriesReviews({required this.auth});

  final AuthRepository auth;

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    return _ServerList(
      auth: auth,
      root: _groceriesRoot,
      path: 'reviews',
      emptyText: s.t('Отзывов пока нет.', 'Пікір әлі жоқ.', 'No reviews yet.'),
      itemBuilder: (context, r, reload) {
        final hidden = r['status'] == 'HIDDEN';
        return Card(
          child: ListTile(
            title: Text('${'★' * _n(r['rating'])} · ${r['store']}'),
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
                    () => auth.authorizedJson('POST',
                            '$_groceriesRoot/reviews/${r['id']}/moderation',
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

class _GroceriesComplaints extends StatelessWidget {
  const _GroceriesComplaints({required this.auth});

  final AuthRepository auth;

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    return _ServerList(
      auth: auth,
      root: _groceriesRoot,
      path: 'complaints',
      emptyText:
          s.t('Открытых жалоб нет.', 'Ашық шағым жоқ.', 'No open complaints.'),
      itemBuilder: (context, c, reload) => Card(
        child: ListTile(
          title: Text('${c['store']}'),
          subtitle: Text(
              '${c['reason']}${c['reviewComment'] == null ? '' : '\n«${c['reviewComment']}»'}\n${_when('${c['createdAt']}')}'),
          isThreeLine: true,
          trailing: TextButton(
            key: const Key('groceries-admin-resolve'),
            onPressed: () async {
              final reason = await _askReason(context,
                  s.t('Закрыть жалобу', 'Шағымды жабу', 'Resolve complaint'));
              if (reason == null || !context.mounted) return;
              await _act(
                  context,
                  () => auth.authorizedJson(
                      'POST', '$_groceriesRoot/complaints/${c['id']}/resolve',
                      body: {'resolution': reason}),
                  reload);
            },
            child: Text(s.t('Закрыть', 'Жабу', 'Resolve')),
          ),
        ),
      ),
    );
  }
}

class _GroceriesAudit extends StatelessWidget {
  const _GroceriesAudit({required this.auth});

  final AuthRepository auth;

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    return _ServerList(
      auth: auth,
      root: _groceriesRoot,
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
