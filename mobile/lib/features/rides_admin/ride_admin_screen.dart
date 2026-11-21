import '../education/education_operations_screen.dart';
import 'package:flutter/material.dart';

import '../admin_employees/admin_employee_screen.dart';
import '../admin_features/admin_features_screen.dart';
import '../auto_admin/auto_admin_screen.dart';
import '../food_admin/food_admin_screen.dart';
import '../leisure_admin/leisure_admin_screen.dart';
import '../delivery_admin/delivery_admin_screen.dart';
import '../identity/auth_repository.dart';
import '../health/health_admin_screen.dart';
import '../rides/ride_strings.dart';

class RideAdminScreen extends StatefulWidget {
  const RideAdminScreen({required this.auth, super.key});

  final AuthRepository auth;

  @override
  State<RideAdminScreen> createState() => _RideAdminScreenState();
}

class _RideAdminScreenState extends State<RideAdminScreen> {
  late Future<(Set<String>, bool)> _permissions = _loadPermissions();

  Future<(Set<String>, bool)> _loadPermissions() async {
    final response = await widget.auth.authorizedJson(
      'GET',
      'admin/me/capabilities',
    );
    final capabilities = response as Map<String, dynamic>;
    return (
      (capabilities['permissions'] as List<dynamic>).cast<String>().toSet(),
      capabilities['deliveryShipmentRead'] == true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('KUNDE Control Center'),
        actions: [
          IconButton(
            onPressed: widget.auth.logout,
            tooltip: s.t('Выйти', 'Шығу', 'Sign out'),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: FutureBuilder<(Set<String>, bool)>(
        future: _permissions,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      s.t(
                        'Не удалось загрузить доступные разделы',
                        'Қолжетімді бөлімдер жүктелмеді',
                        'Could not load available workspaces',
                      ),
                    ),
                    TextButton(
                      onPressed: () =>
                          setState(() => _permissions = _loadPermissions()),
                      child: Text(s.t('Повторить', 'Қайталау', 'Retry')),
                    ),
                  ],
                ),
              ),
            );
          }
          final (permissions, deliveryShipmentRead) = snapshot.requireData;
          final workspaces =
              _workspaces(context, s, permissions, deliveryShipmentRead);
          if (workspaces.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  s.t(
                    'Для этой учётной записи нет доступных очередей',
                    'Бұл есептік жазбаға кезектер қолжетімсіз',
                    'No queues are available for this account',
                  ),
                ),
              ),
            );
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1040;
              final railWidth = wide ? 224.0 : 0.0;
              final contentWidth = constraints.maxWidth - railWidth;
              final columns = contentWidth >= 1080
                  ? 3
                  : contentWidth >= 650
                      ? 2
                      : 1;
              final width = (contentWidth - 32 - 12 * (columns - 1)) / columns;
              final canReadDelivery = deliveryShipmentRead ||
                  permissions.contains('DELIVERY_OPERATIONS');
              final content = SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      s.t('Главная панель', 'Басты панель', 'Overview'),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    if (canReadDelivery)
                      Card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                              child: Row(
                                children: [
                                  Icon(Icons.local_shipping_outlined,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .tertiary),
                                  const SizedBox(width: 12),
                                  Expanded(
                                      child: Text('Delivery',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge)),
                                ],
                              ),
                            ),
                            DeliverySummaryPanel(auth: widget.auth),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
                    ExpansionTile(
                      leading: const Icon(Icons.shield_outlined),
                      title: Text(s.t('Мои разрешения', 'Менің рұқсаттарым',
                          'My permissions')),
                      children: [
                        if (deliveryShipmentRead &&
                            !permissions.contains('DELIVERY_OPERATIONS'))
                          ListTile(
                              title: Text(s.t(
                                  'Delivery · чтение в назначенной области',
                                  'Delivery · тағайындалған ауқымда оқу',
                                  'Delivery · scoped read'))),
                        for (final permission in permissions)
                          ListTile(title: Text(permission)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final workspace in workspaces)
                          SizedBox(width: width, child: workspace),
                      ],
                    ),
                  ],
                ),
              );
              if (!wide) return content;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: railWidth,
                    child: Material(
                      color: const Color(0xff281945),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text('KUNDE',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 24)),
                            const SizedBox(height: 20),
                            if (canReadDelivery)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                textColor: Colors.white,
                                iconColor: Colors.white,
                                leading:
                                    const Icon(Icons.local_shipping_outlined),
                                title: const Text('Delivery'),
                                onTap: () => Navigator.of(context)
                                    .push<void>(MaterialPageRoute(
                                  builder: (_) => DeliveryAdminScreen(
                                    auth: widget.auth,
                                    area: DeliveryAdminArea.shipments,
                                    canRequestReturn: permissions
                                        .contains('DELIVERY_OPERATIONS'),
                                  ),
                                )),
                              ),
                            if (permissions.contains('ADMIN_GRANTS'))
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                textColor: Colors.white,
                                iconColor: Colors.white,
                                leading: const Icon(Icons.badge_outlined),
                                title: Text(s.t(
                                    'Сотрудники', 'Қызметкерлер', 'Employees')),
                                onTap: () => Navigator.of(context)
                                    .push<void>(MaterialPageRoute(
                                  builder: (_) =>
                                      AdminEmployeeScreen(auth: widget.auth),
                                )),
                              ),
                            if (permissions.contains('ADMIN_GRANTS'))
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                textColor: Colors.white,
                                iconColor: Colors.white,
                                leading: const Icon(Icons.toggle_on_outlined),
                                title: Text(
                                    s.t('Функции', 'Функциялар', 'Features')),
                                onTap: () => Navigator.of(context)
                                    .push<void>(MaterialPageRoute(
                                  builder: (_) =>
                                      AdminFeaturesScreen(auth: widget.auth),
                                )),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(child: content),
                ],
              );
            },
          );
        },
      ),
    );
  }

  List<Widget> _workspaces(
    BuildContext context,
    RideStrings s,
    Set<String> permissions,
    bool deliveryShipmentRead,
  ) =>
      [
        if (deliveryShipmentRead || permissions.contains('DELIVERY_OPERATIONS'))
          for (final (area, label, icon) in [
            (
              DeliveryAdminArea.couriers,
              s.t('Курьеры', 'Курьерлер', 'Couriers'),
              Icons.inventory_2_outlined,
            ),
            (
              DeliveryAdminArea.shipments,
              s.t('Отправления', 'Жөнелтілімдер', 'Shipments'),
              Icons.local_shipping_outlined,
            ),
            (
              DeliveryAdminArea.complaints,
              s.t('Жалобы на доставку', 'Жеткізу шағымдары',
                  'Delivery complaints'),
              Icons.flag_outlined,
            ),
          ])
            if (area == DeliveryAdminArea.shipments ||
                permissions.contains('DELIVERY_OPERATIONS'))
              Card(
                child: ListTile(
                  leading: Icon(icon),
                  title: Text(label),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => DeliveryAdminScreen(
                        auth: widget.auth,
                        area: area,
                        canRequestReturn:
                            permissions.contains('DELIVERY_OPERATIONS'),
                      ),
                    ),
                  ),
                ),
              ),
        if (permissions.contains('EDUCATION_OPERATIONS'))
          Card(
            child: ListTile(
              leading: const Icon(Icons.school_outlined),
              title: Text(s.t('Модерация курсов', 'Курстарды модерациялау',
                  'Course moderation')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push<void>(MaterialPageRoute(
                builder: (_) =>
                    EducationOperationsScreen(auth: widget.auth, admin: true),
              )),
            ),
          ),
        if (permissions.contains('FOOD_OPERATIONS'))
          Card(
            child: ListTile(
              leading: const Icon(Icons.restaurant_menu_outlined),
              title: Text(s.t('Еда: центр управления',
                  'Тамақ: басқару орталығы', 'Food control center')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => FoodAdminScreen(auth: widget.auth),
                ),
              ),
            ),
          ),
        if (permissions.contains('GROCERIES_OPERATIONS'))
          Card(
            child: ListTile(
              leading: const Icon(Icons.shopping_basket_outlined),
              title: Text(s.t('Продукты: центр управления',
                  'Азық-түлік: басқару орталығы', 'Groceries control center')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => GroceriesAdminScreen(auth: widget.auth),
                ),
              ),
            ),
          ),
        if (permissions.contains('LEISURE_OPERATIONS'))
          Card(
            child: ListTile(
              leading: const Icon(Icons.confirmation_number_outlined),
              title: Text(s.t('Досуг: центр управления',
                  'Демалыс: басқару орталығы', 'Leisure control center')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => LeisureAdminScreen(auth: widget.auth),
                ),
              ),
            ),
          ),
        if (permissions.contains('HEALTH_OPERATIONS'))
          Card(
            child: ListTile(
              leading: const Icon(Icons.health_and_safety_outlined),
              title: Text(s.t('Здоровье и благополучие',
                  'Денсаулық және әл-ауқат', 'Health & Wellness')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push<void>(MaterialPageRoute(
                builder: (_) => HealthAdminScreen(auth: widget.auth),
              )),
            ),
          ),
        if (permissions.contains('AUTO_OPERATIONS'))
          for (final (area, label, icon) in [
            (
              AutoAdminArea.specialists,
              s.t('Авто-специалисты', 'Авто мамандар', 'Auto specialists'),
              Icons.build_circle_outlined,
            ),
            (
              AutoAdminArea.venues,
              s.t('СТО и автомойки', 'СТО және көлік жуу',
                  'Stations and washes'),
              Icons.garage_outlined,
            ),
            (
              AutoAdminArea.categories,
              s.t('Категории Auto', 'Auto санаттары', 'Auto categories'),
              Icons.category_outlined,
            ),
            (
              AutoAdminArea.bookings,
              s.t('Записи Auto', 'Auto жазылулары', 'Auto bookings'),
              Icons.event_note_outlined,
            ),
            (
              AutoAdminArea.jobs,
              s.t('Выездные заявки', 'Шығу өтінімдері', 'On-site jobs'),
              Icons.emergency_outlined,
            ),
            (
              AutoAdminArea.complaints,
              s.t('Жалобы Auto', 'Auto шағымдары', 'Auto complaints'),
              Icons.report_outlined,
            ),
          ])
            Card(
              child: ListTile(
                leading: Icon(icon),
                title: Text(label),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) =>
                        AutoAdminScreen(auth: widget.auth, area: area),
                  ),
                ),
              ),
            ),
        for (final (route, label, icon) in [
          (
            'drivers',
            s.t('Водители', 'Жүргізушілер', 'Drivers'),
            Icons.person_outline,
          ),
          (
            'fleets',
            s.t('Автопарки', 'Автопарктер', 'Fleets'),
            Icons.local_taxi_outlined,
          ),
          ('trips', s.rides, Icons.route_outlined),
          (
            'complaints',
            s.t('Жалобы', 'Шағымдар', 'Complaints'),
            Icons.flag_outlined,
          ),
        ])
          if (permissions.contains(
            route == 'drivers' || route == 'fleets'
                ? 'RIDE_VERIFICATION'
                : 'RIDE_OPERATIONS',
          ))
            Card(
              child: ListTile(
                leading: Icon(icon),
                title: Text(label),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => _AdminQueue(
                        auth: widget.auth, route: route, label: label),
                  ),
                ),
              ),
            ),
        if (permissions.contains('ADMIN_GRANTS'))
          Card(
            child: ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: Text(s.t('Сотрудники', 'Қызметкерлер', 'Employees')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => AdminEmployeeScreen(auth: widget.auth),
                ),
              ),
            ),
          ),
      ];
}

class _AdminQueue extends StatefulWidget {
  const _AdminQueue(
      {required this.auth, required this.route, required this.label});

  final AuthRepository auth;
  final String route;
  final String label;

  @override
  State<_AdminQueue> createState() => _AdminQueueState();
}

class _AdminQueueState extends State<_AdminQueue> {
  late Future<List<dynamic>> _rows = _loadQueue();
  bool _busy = false;
  Object? _failure;

  Future<List<dynamic>> _loadQueue() => _getList(widget.route == 'drivers'
      ? 'drivers?includeReviewed=true'
      : widget.route);

  Future<List<dynamic>> _getList(String path) async =>
      await widget.auth.authorizedJson('GET', 'admin/rides/$path')
          as List<dynamic>;

  void _reloadQueue() => setState(() {
        _rows = _loadQueue();
      });

  Future<void> _mutate(String path, {Map<String, dynamic>? body}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await widget.auth.authorizedJson('POST', 'admin/rides/$path',
          body: body, expected: {200, 204});
      if (mounted) _reloadQueue();
    } catch (error) {
      if (mounted) setState(() => _failure = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resolve(String id) async {
    final s = RideStrings(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.t(
            'Закрыть жалобу?', 'Шағымды жабу керек пе?', 'Resolve complaint?')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.back)),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.t('Закрыть', 'Жабу', 'Resolve')),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await _mutate('complaints/$id/resolve');
    }
  }

  Future<void> _review(String id, {String? vehicleId}) async {
    final s = RideStrings(context);
    final decision = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.t(
            'Решение модерации', 'Модерация шешімі', 'Moderation decision')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: Text(s.back)),
          TextButton(
            onPressed: () => Navigator.pop(context, 'BLOCKED'),
            child: Text(s.t('Заблокировать', 'Бұғаттау', 'Block')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'APPROVED'),
            child: Text(s.t('Одобрить', 'Мақұлдау', 'Approve')),
          ),
        ],
      ),
    );
    if (decision == null || !mounted) return;
    await _mutate('${widget.route}/$id/decision', body: {
      'decision': decision,
      if (vehicleId != null) 'vehicleId': vehicleId
    });
  }

  Future<void> _audit(String id) async {
    final s = RideStrings(context);
    final events = _getList('${widget.route}/$id/audit');
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.t('Журнал действий', 'Әрекеттер журналы', 'Audit log')),
        content: SizedBox(
          width: 480,
          child: FutureBuilder<List<dynamic>>(
            future: events,
            builder: (context, snapshot) {
              if (snapshot.hasError) return Text(s.error);
              if (!snapshot.hasData) return const LinearProgressIndicator();
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final event
                        in snapshot.data!.cast<Map<String, dynamic>>())
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                            '${event['action'] ?? event['status']} · ${event['occurredAt']}'),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: Text(s.back))
        ],
      ),
    );
  }

  Future<void> _driver(String id) async {
    final s = RideStrings(context);
    final detail = widget.auth.authorizedJson('GET', 'admin/rides/drivers/$id');
    final vehicle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
            s.t('Профиль водителя', 'Жүргізуші профилі', 'Driver profile')),
        content: FutureBuilder<dynamic>(
          future: detail,
          builder: (context, snapshot) {
            if (snapshot.hasError) return Text(s.error);
            if (!snapshot.hasData) return const LinearProgressIndicator();
            final driver = snapshot.data as Map<String, dynamic>;
            final car = driver['vehicle'] as Map<String, dynamic>?;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${driver['displayName']} · ${driver['status']}'),
                if (car != null)
                  Text(
                      '${car['description']} · ${car['plate']} · ${car['status']}'),
                if (car != null)
                  TextButton(
                    onPressed: () =>
                        Navigator.pop(context, car['id'] as String),
                    child: Text(s.t('Проверить автомобиль', 'Көлікті тексеру',
                        'Review vehicle')),
                  ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, ''),
                  child: Text(s.t('Проверить водителя', 'Жүргізушіні тексеру',
                      'Review driver')),
                ),
              ],
            );
          },
        ),
      ),
    );
    if (vehicle != null && mounted) {
      await _review(id, vehicleId: vehicle.isEmpty ? null : vehicle);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.label),
        actions: [
          IconButton(
            onPressed: _busy ? null : _reloadQueue,
            tooltip: s.retry,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _rows,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            final error = snapshot.error;
            return Center(
                child: Text(error is IdentityApiError && error.status == 403
                    ? s.t('Доступ запрещён', 'Рұқсат жоқ', 'Access denied')
                    : s.error));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (_failure != null)
                Semantics(liveRegion: true, child: Text(s.error)),
              if (snapshot.data!.isEmpty)
                Text(s.t('Нет записей', 'Жазбалар жоқ', 'No records')),
              for (final row in snapshot.data!) _record(s, row),
            ],
          );
        },
      ),
    );
  }

  Widget _record(RideStrings s, Object? raw) {
    final row = raw is Map<String, dynamic> ? raw : {'id': raw};
    final id = row['id'] as String;
    final status = row['status'] as String?;
    return Card(
      child: ListTile(
        title: Text(row['name'] as String? ?? row['message'] as String? ?? id),
        subtitle: status == null
            ? null
            : Text(widget.route == 'trips'
                ? [if (row['synthetic'] == true) s.synthetic, s.status(status)]
                    .join(' · ')
                : status),
        trailing: widget.route == 'trips'
            ? null
            : PopupMenuButton<int>(
                enabled: !_busy,
                onSelected: (action) {
                  if (action == 0) {
                    _audit(id);
                  } else if (widget.route == 'drivers') {
                    _driver(id);
                  } else if (widget.route == 'fleets') {
                    _review(id);
                  } else {
                    _resolve(id);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                      value: 0, child: Text(s.t('Аудит', 'Аудит', 'Audit'))),
                  if (status != 'RESOLVED')
                    PopupMenuItem(
                      value: 1,
                      child: Text(widget.route == 'complaints'
                          ? s.t('Закрыть жалобу', 'Шағымды жабу',
                              'Resolve complaint')
                          : s.t('Рассмотреть', 'Қарау', 'Review')),
                    ),
                ],
              ),
      ),
    );
  }
}
