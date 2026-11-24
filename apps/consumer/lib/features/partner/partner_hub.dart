import '../beauty/presentation/beauty_partner_entry.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:kunde_localization/kunde_formats.dart';
import 'package:kunde_models/booking_models.dart';
import 'package:kunde_auth/auth_repository.dart';
import 'partner_ops_api.dart';
import 'partner_panel.dart' show parseKztToTiyn, invalidPrice;

String _t(BuildContext context, String ru, String kk, String en) {
  final locale = Localizations.localeOf(context).languageCode;
  return locale == 'kk'
      ? kk
      : locale == 'en'
          ? en
          : ru;
}

String _money(BuildContext context, num minor) =>
    KundeFormats.money(minor.toInt(), 'KZT', Localizations.localeOf(context));

/// Human-readable failure of a partner action. 409 means the state changed meanwhile (the caller reloads).
String _failureText(BuildContext context, Object error) {
  if (error is SessionExpired) {
    return _t(context, 'Сессия истекла', 'Сессия аяқталды', 'Session expired');
  }
  if (error is IdentityApiError) {
    switch (error.code) {
      case 'ORDER_TRANSITION_INVALID':
      case 'BOOKING_TRANSITION_INVALID':
        return _t(
            context,
            'Статус уже изменился. Список обновлён.',
            'Күй өзгерді. Тізім жаңартылды.',
            'The status has changed. The list was refreshed.');
      case 'SCHEDULE_CONFLICT':
        return _t(
            context,
            'Есть записи, которые не вписываются в новое расписание',
            'Жаңа кестеге сыймайтын жазылулар бар',
            'Existing bookings do not fit the new schedule');
      case 'REASON_REQUIRED':
        return _t(
            context,
            'Укажите причину (3–300 символов)',
            'Себебін көрсетіңіз (3–300 таңба)',
            'Enter a reason (3–300 characters)');
      case 'PARTNER_ROLE_FORBIDDEN':
        return _t(
            context,
            'Для этого действия нужна роль менеджера',
            'Бұл әрекет үшін менеджер рөлі қажет',
            'This needs the manager role');
      case 'PARTNER_NOT_APPROVED':
        return _t(context, 'Партнёр ещё не одобрен',
            'Серіктес әлі мақұлданбаған', 'The partner is not approved yet');
      case 'NAME_INVALID':
        return _t(context, 'Название: от 2 до 160 символов',
            'Атауы: 2–160 таңба', 'Name must be 2–160 characters');
      case 'PRICE_INVALID':
        return _t(context, 'Цена от 0 до 1 000 000 ₸', 'Бағасы 0–1 000 000 ₸',
            'Price must be 0–1,000,000 KZT');
      case 'DISH_NAME_TAKEN':
        return _t(context, 'Блюдо с таким названием уже есть',
            'Мұндай атаулы тағам бар', 'A dish with this name already exists');
      case 'HOURS_INVALID':
        return _t(
            context,
            'Проверьте время: конец позже начала',
            'Уақытты тексеріңіз: аяқталуы басталуынан кейін',
            'Check the time: end after start');
    }
  }
  return _t(
      context,
      'Не удалось выполнить. Повторите позже.',
      'Орындау мүмкін болмады. Кейінірек қайталаңыз.',
      'Could not complete. Try again later.');
}

void _toast(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

Future<String?> _askReason(BuildContext context, String title) =>
    showDialog<String>(
      context: context,
      builder: (context) => _ReasonDialog(title: title),
    );

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
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          controller: _controller,
          maxLength: 300,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
              labelText: _t(
                  context,
                  'Причина (видна клиенту)',
                  'Себебі (клиентке көрінеді)',
                  'Reason (shown to the customer)')),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_t(context, 'Назад', 'Артқа', 'Back'))),
          FilledButton(
              onPressed: _controller.text.trim().length < 3
                  ? null
                  : () => Navigator.pop(context, _controller.text.trim()),
              child: Text(_t(context, 'Подтвердить', 'Растау', 'Confirm'))),
        ],
      );
}

/// Operations hub of one APPROVED partner: incoming orders, bookings and availability. Reached only from the profile's
/// partner section, which lists only partners the server reports for the signed-in user.
class PartnerHubPage extends StatelessWidget {
  const PartnerHubPage({required this.auth, required this.partner, super.key});
  final AuthRepository auth;
  final Map<String, dynamic> partner;

  @override
  Widget build(BuildContext context) {
    final api = PartnerOpsApi(auth, partner['id'] as String);
    final canManage = partner['role'] != 'OPERATOR';
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(partner['displayName'] as String),
          actions: [
            BeautyPartnerEntry(auth: auth, partnerId: partner['id'] as String),
          ],
          bottom: TabBar(tabs: [
            Tab(text: _t(context, 'Заказы', 'Тапсырыстар', 'Orders')),
            Tab(text: _t(context, 'Записи', 'Жазылулар', 'Bookings')),
            Tab(
                text: _t(
                    context, 'Доступность', 'Қолжетімділік', 'Availability')),
          ]),
        ),
        body: TabBarView(children: [
          _FoodOrdersTab(api: api),
          _BookingsTab(api: api),
          _AvailabilityTab(api: api, canManage: canManage),
        ]),
      ),
    );
  }
}

/// Shared load/poll/refresh behavior of the list tabs.
mixin _Polling<T extends StatefulWidget> on State<T> {
  Timer? _timer;
  bool loading = true;
  bool failed = false;

  Future<void> load();

  void startPolling() {
    reload();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => load());
  }

  Future<void> reload() async {
    if (mounted) setState(() => loading = true);
    await load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

Widget _statusChip(BuildContext context, String label, Color color) => Chip(
      label: Text(label),
      backgroundColor: color,
      visualDensity: VisualDensity.compact,
      side: BorderSide.none,
    );

/// Plays the system alert and haptic tap and shows a banner: the partner is working in the open app (no push provider yet).
void _alertNew(BuildContext context, String text) {
  SystemSound.play(SystemSoundType.alert);
  HapticFeedback.heavyImpact();
  _toast(context, text);
}

// ---------------------------------------------------------------------------------------------------------------------
// Orders
// ---------------------------------------------------------------------------------------------------------------------

String _orderStatus(BuildContext context, String status) => switch (status) {
      'PLACED' => _t(context, 'Новый', 'Жаңа', 'New'),
      'ACCEPTED' => _t(context, 'Принят', 'Қабылданды', 'Accepted'),
      'PREPARING' => _t(context, 'Готовится', 'Дайындалуда', 'Preparing'),
      'ON_THE_WAY' => _t(context, 'В пути', 'Жолда', 'On the way'),
      'DELIVERED' => _t(context, 'Доставлен', 'Жеткізілді', 'Delivered'),
      'CANCELLED' => _t(context, 'Отменён', 'Бас тартылды', 'Cancelled'),
      _ => status,
    };

String _orderAction(BuildContext context, String next) => switch (next) {
      'ACCEPTED' => _t(context, 'Принять', 'Қабылдау', 'Accept'),
      'PREPARING' => _t(context, 'Готовить', 'Дайындау', 'Start preparing'),
      'ON_THE_WAY' => _t(context, 'Передан в доставку', 'Жеткізуге берілді',
          'Out for delivery'),
      'DELIVERED' => _t(context, 'Доставлен', 'Жеткізілді', 'Delivered'),
      'CANCELLED' => _t(context, 'Отклонить', 'Бас тарту', 'Reject'),
      _ => next,
    };

class _FoodOrdersTab extends StatefulWidget {
  const _FoodOrdersTab({required this.api});
  final PartnerOpsApi api;

  @override
  State<_FoodOrdersTab> createState() => _FoodOrdersTabState();
}

class _FoodOrdersTabState extends State<_FoodOrdersTab> with _Polling {
  String _scope = 'active';
  List<Map<String, dynamic>> _orders = const [];
  String? _busyId;
  Set<String>?
      _seenNew; // null until the first load, so opening the tab is silent

  @override
  void initState() {
    super.initState();
    startPolling();
  }

  @override
  Future<void> load() async {
    try {
      final orders = await widget.api.foodOrders(_scope);
      if (!mounted) return;
      if (_scope == 'active') {
        final fresh = {
          for (final entry in orders)
            if ((entry['order'] as Map)['status'] == 'PLACED')
              (entry['order'] as Map)['id'] as String
        };
        final seen = _seenNew;
        _seenNew = {...?seen, ...fresh};
        if (seen != null && fresh.any((id) => !seen.contains(id))) {
          _alertNew(context,
              _t(context, 'Новый заказ!', 'Жаңа тапсырыс!', 'New order!'));
        }
      }
      setState(() {
        _orders = orders;
        loading = false;
        failed = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          failed = true;
        });
      }
    }
  }

  Future<void> _move(Map<String, dynamic> entry, String next) async {
    final order = entry['order'] as Map<String, dynamic>;
    String? reason;
    if (next == 'CANCELLED') {
      reason = await _askReason(
          context,
          _t(context, 'Отклонить заказ', 'Тапсырыстан бас тарту',
              'Reject the order'));
      if (reason == null || !mounted) return;
    }
    setState(() => _busyId = order['id'] as String);
    try {
      await widget.api
          .setFoodOrderStatus(order['id'] as String, next, reason: reason);
    } catch (error) {
      if (mounted) _toast(context, _failureText(context, error));
    } finally {
      if (mounted) setState(() => _busyId = null);
      await load();
    }
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SegmentedButton<String>(
            segments: [
              ButtonSegment(
                  value: 'active',
                  label: Text(_t(context, 'Активные', 'Белсенді', 'Active'))),
              ButtonSegment(
                  value: 'history',
                  label: Text(_t(context, 'История', 'Тарих', 'History'))),
            ],
            selected: {_scope},
            onSelectionChanged: (value) {
              _scope = value.first;
              reload();
            },
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: reload,
            child: loading && _orders.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : failed && _orders.isEmpty
                    ? ListView(children: [
                        const SizedBox(height: 80),
                        Center(
                            child: TextButton(
                                onPressed: reload,
                                child: Text(_t(
                                    context,
                                    'Ошибка загрузки — повторить',
                                    'Жүктеу қатесі — қайталау',
                                    'Loading failed — retry')))),
                      ])
                    : _orders.isEmpty
                        ? ListView(children: [
                            const SizedBox(height: 80),
                            Center(
                                child: Text(_scope == 'active'
                                    ? _t(context, 'Новых заказов нет',
                                        'Жаңа тапсырыстар жоқ', 'No new orders')
                                    : _t(context, 'История пуста', 'Тарих бос',
                                        'No history yet'))),
                          ])
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                            children: [
                              for (final entry in _orders)
                                _OrderCard(
                                  key: ValueKey((entry['order'] as Map)['id']),
                                  entry: entry,
                                  busy:
                                      _busyId == (entry['order'] as Map)['id'],
                                  onMove: (next) => _move(entry, next),
                                ),
                            ],
                          ),
          ),
        ),
      ]);
}

class _OrderCard extends StatelessWidget {
  const _OrderCard(
      {required this.entry,
      required this.busy,
      required this.onMove,
      super.key});
  final Map<String, dynamic> entry;
  final bool busy;
  final void Function(String next) onMove;

  @override
  Widget build(BuildContext context) {
    final order = entry['order'] as Map<String, dynamic>;
    final status = order['status'] as String;
    final next = (entry['allowedNext'] as List<dynamic>).cast<String>();
    final items =
        (order['items'] as List<dynamic>).cast<Map<String, dynamic>>();
    final timeline =
        (order['timeline'] as List<dynamic>).cast<Map<String, dynamic>>();
    final theme = Theme.of(context);
    final color = status == 'CANCELLED'
        ? theme.colorScheme.errorContainer
        : status == 'PLACED'
            ? const Color(0xFFFFE9C7)
            : const Color(0xFFDDF4E2);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: theme.colorScheme.outlineVariant)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(
                    '${order['restaurantName']} · #${entry['customerRef']}',
                    style: theme.textTheme.titleMedium)),
            _statusChip(context, _orderStatus(context, status), color),
          ]),
          const SizedBox(height: 6),
          for (final item in items)
            Text('${item['quantity']} × ${item['name']}'
                '${(item['optionsText'] as String).isEmpty ? '' : ' (${item['optionsText']})'}'),
          const SizedBox(height: 6),
          Text('${_t(context, 'Итого', 'Барлығы', 'Total')}: '
              '${_money(context, order['totalMinor'] as num)} · '
              '${order['paymentMethod'] == 'CASH_ON_DELIVERY' ? _t(context, 'наличными', 'қолма-қол', 'cash') : _t(context, 'тест-карта (DEV)', 'тест-карта (DEV)', 'test card (DEV)')}'),
          Text('${order['addressLabel']}: ${order['addressText']}',
              style: theme.textTheme.bodySmall),
          if ((order['comment'] as String?)?.isNotEmpty ?? false)
            Text('«${order['comment']}»', style: theme.textTheme.bodySmall),
          if (order['cancelReason'] != null)
            Text(
                '${_t(context, 'Причина', 'Себебі', 'Reason')}: ${order['cancelReason'] == 'PARTNER_TIMEOUT' ? _t(context, 'не ответили вовремя', 'уақытында жауап берілмеді', 'not answered in time') : order['cancelReason']}',
                style: theme.textTheme.bodySmall),
          if (entry['respondBy'] != null) _RespondBy(entry: entry),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(
                _t(context, 'История статусов', 'Күй тарихы', 'Status history'),
                style: theme.textTheme.labelLarge),
            children: [
              for (final step in timeline)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(_orderStatus(context, step['status'] as String)),
                  subtitle: Text(
                      '${formatDay(parseVenueTime(step['at'] as String))}, ${formatClock(parseVenueTime(step['at'] as String))}'
                      '${step['actor'] == null ? '' : ' · ${step['actor'] == 'PARTNER' ? _t(context, 'партнёр', 'серіктес', 'partner') : step['actor'] == 'CUSTOMER' ? _t(context, 'клиент', 'клиент', 'customer') : _t(context, 'система', 'жүйе', 'system')}'}'
                      '${step['reason'] == null ? '' : ' · ${step['reason']}'}'),
                ),
            ],
          ),
          if (next.isNotEmpty)
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final target in next)
                target == 'CANCELLED'
                    ? OutlinedButton(
                        onPressed: busy ? null : () => onMove(target),
                        child: Text(_orderAction(context, target)))
                    : FilledButton(
                        onPressed: busy ? null : () => onMove(target),
                        child: Text(_orderAction(context, target))),
            ]),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// Bookings
// ---------------------------------------------------------------------------------------------------------------------

String _bookingStatus(BuildContext context, String status) => switch (status) {
      'PENDING' => _t(context, 'Ждёт ответа', 'Жауап күтеді', 'Awaiting reply'),
      'CONFIRMED' => _t(context, 'Подтверждена', 'Расталды', 'Confirmed'),
      'COMPLETED' => _t(context, 'Состоялась', 'Өтті', 'Completed'),
      'CANCELLED' => _t(context, 'Отменена', 'Бас тартылды', 'Cancelled'),
      _ => status,
    };

String _bookingAction(BuildContext context, String action) => switch (action) {
      'CONFIRM' => _t(context, 'Подтвердить', 'Растау', 'Confirm'),
      'REJECT' => _t(context, 'Отклонить', 'Бас тарту', 'Reject'),
      'CANCEL' => _t(context, 'Отменить', 'Болдырмау', 'Cancel'),
      'COMPLETE' => _t(context, 'Завершить', 'Аяқтау', 'Complete'),
      _ => action,
    };

class _BookingsTab extends StatefulWidget {
  const _BookingsTab({required this.api});
  final PartnerOpsApi api;

  @override
  State<_BookingsTab> createState() => _BookingsTabState();
}

class _BookingsTabState extends State<_BookingsTab> with _Polling {
  String _scope = 'requests';
  List<Map<String, dynamic>> _bookings = const [];
  String? _busyId;
  Set<String>? _seenNew;

  @override
  void initState() {
    super.initState();
    startPolling();
  }

  @override
  Future<void> load() async {
    try {
      final bookings = await widget.api.bookings(_scope);
      if (!mounted) return;
      if (_scope == 'requests') {
        final fresh = {for (final b in bookings) b['id'] as String};
        final seen = _seenNew;
        _seenNew = {...?seen, ...fresh};
        if (seen != null && fresh.any((id) => !seen.contains(id))) {
          _alertNew(
              context,
              _t(context, 'Новая запись!', 'Жаңа жазылу!',
                  'New booking request!'));
        }
      }
      setState(() {
        _bookings = bookings;
        loading = false;
        failed = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          failed = true;
        });
      }
    }
  }

  Future<void> _act(Map<String, dynamic> booking, String action) async {
    String? reason;
    if (action == 'REJECT' || action == 'CANCEL') {
      reason = await _askReason(
          context,
          action == 'REJECT'
              ? _t(context, 'Отклонить запись', 'Жазылудан бас тарту',
                  'Reject the booking')
              : _t(context, 'Отменить запись', 'Жазылуды болдырмау',
                  'Cancel the booking'));
      if (reason == null || !mounted) return;
    }
    setState(() => _busyId = booking['id'] as String);
    try {
      await widget.api
          .bookingAction(booking['id'] as String, action, reason: reason);
    } catch (error) {
      if (mounted) _toast(context, _failureText(context, error));
    } finally {
      if (mounted) setState(() => _busyId = null);
      await load();
    }
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SegmentedButton<String>(
            segments: [
              ButtonSegment(
                  value: 'requests',
                  label: Text(_t(context, 'Заявки', 'Өтінімдер', 'Requests'))),
              ButtonSegment(
                  value: 'upcoming',
                  label:
                      Text(_t(context, 'Предстоящие', 'Алдағы', 'Upcoming'))),
              ButtonSegment(
                  value: 'history',
                  label: Text(_t(context, 'История', 'Тарих', 'History'))),
            ],
            selected: {_scope},
            onSelectionChanged: (value) {
              _scope = value.first;
              reload();
            },
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: reload,
            child: loading && _bookings.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : failed && _bookings.isEmpty
                    ? ListView(children: [
                        const SizedBox(height: 80),
                        Center(
                            child: TextButton(
                                onPressed: reload,
                                child: Text(_t(
                                    context,
                                    'Ошибка загрузки — повторить',
                                    'Жүктеу қатесі — қайталау',
                                    'Loading failed — retry')))),
                      ])
                    : _bookings.isEmpty
                        ? ListView(children: [
                            const SizedBox(height: 80),
                            Center(
                                child: Text(_t(context, 'Записей нет',
                                    'Жазылулар жоқ', 'No bookings'))),
                          ])
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                            children: [
                              for (final booking in _bookings)
                                _BookingCard(
                                  key: ValueKey(booking['id']),
                                  booking: booking,
                                  busy: _busyId == booking['id'],
                                  onAction: (action) => _act(booking, action),
                                ),
                            ],
                          ),
          ),
        ),
      ]);
}

class _BookingCard extends StatelessWidget {
  const _BookingCard(
      {required this.booking,
      required this.busy,
      required this.onAction,
      super.key});
  final Map<String, dynamic> booking;
  final bool busy;
  final void Function(String action) onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = booking['status'] as String;
    final start = parseVenueTime(booking['startsAt'] as String);
    final end = parseVenueTime(booking['endsAt'] as String);
    final actions = (booking['allowedActions'] as List<dynamic>).cast<String>();
    final timeline =
        (booking['timeline'] as List<dynamic>).cast<Map<String, dynamic>>();
    final color = status == 'CANCELLED'
        ? theme.colorScheme.errorContainer
        : status == 'PENDING'
            ? const Color(0xFFFFE9C7)
            : const Color(0xFFDDF4E2);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: theme.colorScheme.outlineVariant)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(
                    '${booking['serviceName']} · #${booking['customerRef']}',
                    style: theme.textTheme.titleMedium)),
            _statusChip(context, _bookingStatus(context, status), color),
          ]),
          const SizedBox(height: 4),
          Text(
              '${formatDay(start)}, ${formatClock(start)}–${formatClock(end)} · '
              '${booking['durationMinutes']} ${_t(context, 'мин', 'мин', 'min')}'),
          Text(
              '${_t(context, 'Мастер', 'Шебер', 'Staff')}: ${booking['masterName']} · '
              '${_money(context, booking['priceMinor'] as num)}'),
          if (booking['addressText'] != null)
            Text(
                '${booking['addressText']}'
                '${booking['areaSqm'] == null ? '' : ' · ${booking['areaSqm']} м²'}',
                style: theme.textTheme.bodySmall),
          if ((booking['comment'] as String?)?.isNotEmpty ?? false)
            Text('«${booking['comment']}»', style: theme.textTheme.bodySmall),
          if (booking['cancelReason'] != null)
            Text(
                '${_t(context, 'Причина', 'Себебі', 'Reason')}: ${booking['cancelReason']}',
                style: theme.textTheme.bodySmall),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(_t(context, 'История', 'Тарих', 'History'),
                style: theme.textTheme.labelLarge),
            children: [
              for (final step in timeline)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title:
                      Text(_bookingStatus(context, step['status'] as String)),
                  subtitle: Text(
                      '${formatDay(parseVenueTime(step['at'] as String))}, ${formatClock(parseVenueTime(step['at'] as String))}'
                      '${step['reason'] == null ? '' : ' · ${step['reason']}'}'),
                ),
            ],
          ),
          if (actions.isNotEmpty)
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final action in actions)
                action == 'CONFIRM' || action == 'COMPLETE'
                    ? FilledButton(
                        onPressed: busy ? null : () => onAction(action),
                        child: Text(_bookingAction(context, action)))
                    : OutlinedButton(
                        onPressed: busy ? null : () => onAction(action),
                        child: Text(_bookingAction(context, action))),
            ]),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// Availability: restaurants (open, dishes, stock) and venues (open, services, masters, weekly hours)
// ---------------------------------------------------------------------------------------------------------------------

class _AvailabilityTab extends StatefulWidget {
  const _AvailabilityTab({required this.api, required this.canManage});
  final PartnerOpsApi api;
  final bool canManage;

  @override
  State<_AvailabilityTab> createState() => _AvailabilityTabState();
}

class _AvailabilityTabState extends State<_AvailabilityTab> {
  late Future<(List<Map<String, dynamic>>, List<Map<String, dynamic>>)> _data;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _data = (() async =>
        (await widget.api.restaurants(), await widget.api.venues()))();
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) _toast(context, _failureText(context, error));
    }
    if (mounted) setState(_reload);
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<(List<Map<String, dynamic>>, List<Map<String, dynamic>>)>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
                child: TextButton(
                    onPressed: () => setState(_reload),
                    child: Text(_t(
                        context,
                        'Ошибка загрузки — повторить',
                        'Жүктеу қатесі — қайталау',
                        'Loading failed — retry'))));
          }
          final (restaurants, venues) = snapshot.data!;
          if (restaurants.isEmpty && venues.isEmpty) {
            return Center(
                child: Text(_t(
                    context,
                    'К партнёру не привязаны рестораны и заведения',
                    'Серіктеске мекемелер байланыстырылмаған',
                    'No restaurants or venues are linked to this partner')));
          }
          return RefreshIndicator(
            onRefresh: () async {
              setState(_reload);
              await _data;
            },
            child: ListView(padding: const EdgeInsets.all(12), children: [
              for (final restaurant in restaurants)
                _RestaurantSection(
                    key: ValueKey(restaurant['id']),
                    api: widget.api,
                    restaurant: restaurant,
                    canManage: widget.canManage,
                    guard: _guard),
              for (final venue in venues)
                _VenueSection(
                    key: ValueKey(venue['id']),
                    api: widget.api,
                    venue: venue,
                    canManage: widget.canManage,
                    guard: _guard),
            ]),
          );
        },
      );
}

typedef _Guard = Future<void> Function(Future<void> Function() action);

class _RestaurantSection extends StatelessWidget {
  const _RestaurantSection(
      {required this.api,
      required this.restaurant,
      required this.canManage,
      required this.guard,
      super.key});
  final PartnerOpsApi api;
  final Map<String, dynamic> restaurant;
  final bool canManage;
  final _Guard guard;

  Future<void> _editStock(
      BuildContext context, Map<String, dynamic> dish) async {
    final value = await showDialog<String>(
        context: context,
        builder: (context) => _StockDialog(current: dish['stockQty'] as int?));
    if (value == null) return;
    await guard(() async {
      if (value.isEmpty) {
        await api.updateDish(restaurant['id'] as String, dish['id'] as String,
            clearStock: true);
      } else {
        await api.updateDish(restaurant['id'] as String, dish['id'] as String,
            stockQty: int.parse(value));
      }
    });
  }

  Future<void> _editDish(
      BuildContext context, Map<String, dynamic> dish) async {
    final draft = await showDialog<_DishDraft>(
        context: context, builder: (context) => _DishDialog(dish: dish));
    if (draft == null) return;
    await guard(() async {
      await api.updateDish(restaurant['id'] as String, dish['id'] as String,
          name: draft.name,
          description: draft.description,
          priceMinor: draft.priceMinor);
    });
  }

  Future<void> _addDish(
      BuildContext context, List<Map<String, dynamic>> dishes) async {
    final sections = <String, String>{
      for (final dish in dishes)
        dish['sectionId'] as String: dish['section'] as String,
    };
    final draft = await showDialog<_DishDraft>(
        context: context,
        builder: (context) => _DishDialog(sections: sections));
    if (draft == null) return;
    await guard(() async {
      await api.createDish(restaurant['id'] as String,
          sectionId: draft.sectionId!,
          name: draft.name,
          description: draft.description,
          priceMinor: draft.priceMinor);
    });
  }

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        elevation: 0,
        color: Colors.white,
        child: ExpansionTile(
          title: Text(restaurant['name'] as String),
          subtitle: Text(restaurant['vertical'] == 'GROCERY'
              ? _t(context, 'Магазин', 'Дүкен', 'Store')
              : _t(context, 'Ресторан', 'Мейрамхана', 'Restaurant')),
          children: [
            SwitchListTile(
              title: Text(_t(context, 'Принимает заказы', 'Тапсырыс қабылдайды',
                  'Accepting orders')),
              value: restaurant['open'] as bool,
              onChanged: canManage
                  ? (value) => guard(() async {
                        await api.setRestaurantOpen(
                            restaurant['id'] as String, value);
                      })
                  : null,
            ),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: api.dishes(restaurant['id'] as String),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const LinearProgressIndicator();
                }
                final dishes = snapshot.data ?? const <Map<String, dynamic>>[];
                return Column(children: [
                  for (final dish in dishes)
                    SwitchListTile(
                      key: ValueKey(dish['id']),
                      title: Text(dish['name'] as String),
                      subtitle: InkWell(
                        onTap: () => _editStock(context, dish),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                              '${_money(context, dish['priceMinor'] as num)} · '
                              '${_t(context, 'остаток', 'қалдық', 'stock')}: '
                              '${dish['stockQty'] ?? _t(context, 'без учёта', 'есепсіз', 'untracked')} ✎'),
                        ),
                      ),
                      value: dish['available'] as bool,
                      secondary: canManage
                          ? IconButton(
                              tooltip:
                                  _t(context, 'Изменить', 'Өзгерту', 'Edit'),
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _editDish(context, dish),
                            )
                          : null,
                      onChanged: (value) => guard(() async {
                        await api.updateDish(
                            restaurant['id'] as String, dish['id'] as String,
                            available: value);
                      }),
                    ),
                  if (canManage && dishes.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        icon: const Icon(Icons.add),
                        label: Text(_t(context, 'Добавить блюдо', 'Тағам қосу',
                            'Add a dish')),
                        onPressed: () => _addDish(context, dishes),
                      ),
                    ),
                ]);
              },
            ),
          ],
        ),
      );
}

class _DishDraft {
  const _DishDraft(
      {required this.name,
      required this.description,
      required this.priceMinor,
      this.sectionId});
  final String name;
  final String description;
  final int priceMinor;
  final String? sectionId;
}

/// Edit a dish (name, description, price in KZT) or, with [sections], add a new one to a chosen menu section.
class _DishDialog extends StatefulWidget {
  const _DishDialog({this.dish, this.sections});
  final Map<String, dynamic>? dish;
  final Map<String, String>? sections;

  @override
  State<_DishDialog> createState() => _DishDialogState();
}

class _DishDialogState extends State<_DishDialog> {
  late final _name =
      TextEditingController(text: widget.dish?['name'] as String? ?? '');
  late final _description =
      TextEditingController(text: widget.dish?['description'] as String? ?? '');
  late final _price = TextEditingController(
      text: widget.dish == null
          ? ''
          : ((widget.dish!['priceMinor'] as num) / 100)
              .toStringAsFixed(2)
              .replaceFirst(RegExp(r'\.00$'), ''));
  String? _section;

  @override
  void initState() {
    super.initState();
    _section = widget.sections?.keys.first;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    super.dispose();
  }

  int? get _priceMinor {
    final value = parseKztToTiyn(_price.text);
    return value == null || value == invalidPrice ? null : value;
  }

  bool get _valid =>
      _name.text.trim().length >= 2 &&
      _priceMinor != null &&
      _priceMinor! <= 100000000;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.dish == null
            ? _t(context, 'Новое блюдо', 'Жаңа тағам', 'New dish')
            : _t(context, 'Блюдо', 'Тағам', 'Dish')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (widget.sections != null && widget.sections!.length > 1)
              DropdownButtonFormField<String>(
                initialValue: _section,
                items: [
                  for (final entry in widget.sections!.entries)
                    DropdownMenuItem(
                        value: entry.key, child: Text(entry.value)),
                ],
                onChanged: (value) => setState(() => _section = value),
                decoration: InputDecoration(
                    labelText: _t(context, 'Раздел меню', 'Мәзір бөлімі',
                        'Menu section')),
              ),
            TextField(
              controller: _name,
              maxLength: 160,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                  labelText: _t(context, 'Название', 'Атауы', 'Name')),
            ),
            TextField(
              controller: _description,
              maxLength: 500,
              decoration: InputDecoration(
                  labelText:
                      _t(context, 'Описание', 'Сипаттама', 'Description')),
            ),
            TextField(
              controller: _price,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                  labelText: _t(context, 'Цена, ₸', 'Бағасы, ₸', 'Price, KZT')),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_t(context, 'Отмена', 'Бас тарту', 'Cancel'))),
          FilledButton(
              onPressed: _valid
                  ? () => Navigator.pop(
                      context,
                      _DishDraft(
                          name: _name.text.trim(),
                          description: _description.text.trim(),
                          priceMinor: _priceMinor!,
                          sectionId: _section))
                  : null,
              child: Text(_t(context, 'Сохранить', 'Сақтау', 'Save'))),
        ],
      );
}

class _StockDialog extends StatefulWidget {
  const _StockDialog({required this.current});
  final int? current;

  @override
  State<_StockDialog> createState() => _StockDialogState();
}

class _StockDialogState extends State<_StockDialog> {
  late final _controller =
      TextEditingController(text: widget.current?.toString() ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _valid {
    final text = _controller.text.trim();
    if (text.isEmpty) return true;
    final value = int.tryParse(text);
    return value != null && value >= 0 && value <= 100000;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(_t(context, 'Остаток', 'Қалдық', 'Stock')),
        content: TextField(
          controller: _controller,
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
              helperText: _t(
                  context,
                  'Пусто — без учёта остатков',
                  'Бос — қалдық есепке алынбайды',
                  'Empty — stock is not tracked')),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_t(context, 'Отмена', 'Бас тарту', 'Cancel'))),
          FilledButton(
              onPressed: _valid
                  ? () => Navigator.pop(context, _controller.text.trim())
                  : null,
              child: Text(_t(context, 'Сохранить', 'Сақтау', 'Save'))),
        ],
      );
}

class _VenueSection extends StatelessWidget {
  const _VenueSection(
      {required this.api,
      required this.venue,
      required this.canManage,
      required this.guard,
      super.key});
  final PartnerOpsApi api;
  final Map<String, dynamic> venue;
  final bool canManage;
  final _Guard guard;

  String get _id => venue['id'] as String;

  Future<void> _editHours(
      BuildContext context, Map<String, dynamic> master) async {
    final hours =
        (master['hours'] as List<dynamic>).cast<Map<String, dynamic>>();
    final result = await showDialog<List<Map<String, dynamic>>>(
        context: context, builder: (context) => _HoursDialog(hours: hours));
    if (result == null) return;
    await guard(() async {
      await api.setMasterHours(_id, master['id'] as String, result);
    });
  }

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        elevation: 0,
        color: Colors.white,
        child: ExpansionTile(
          title: Text(venue['name'] as String),
          subtitle: Text(venue['category'] == 'CLEANING'
              ? _t(context, 'Дом и быт', 'Үй және тұрмыс', 'Home services')
              : _t(context, 'Красота', 'Сұлулық', 'Beauty')),
          children: [
            SwitchListTile(
              title: Text(_t(context, 'Принимает записи', 'Жазылу қабылдайды',
                  'Accepting bookings')),
              value: venue['open'] as bool,
              onChanged: canManage
                  ? (value) => guard(() async {
                        await api.setVenueOpen(_id, value);
                      })
                  : null,
            ),
            FutureBuilder<List<List<Map<String, dynamic>>>>(
              future: Future.wait([api.services(_id), api.masters(_id)]),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const LinearProgressIndicator();
                }
                final data = snapshot.data;
                if (data == null) return const SizedBox.shrink();
                return Column(children: [
                  Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          child: Text(
                              _t(context, 'Услуги', 'Қызметтер', 'Services'),
                              style: Theme.of(context).textTheme.titleSmall))),
                  for (final service in data[0])
                    SwitchListTile(
                      key: ValueKey(service['id']),
                      title: Text(service['name'] as String),
                      subtitle: Text(
                          '${_money(context, service['priceMinor'] as num)} · '
                          '${service['durationMinutes']} ${_t(context, 'мин', 'мин', 'min')}'),
                      value: service['available'] as bool,
                      onChanged: (value) => guard(() async {
                        await api.setServiceAvailable(
                            _id, service['id'] as String, value);
                      }),
                    ),
                  Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          child: Text(
                              _t(context, 'Мастера и расписание',
                                  'Шеберлер және кесте', 'Staff and schedule'),
                              style: Theme.of(context).textTheme.titleSmall))),
                  for (final master in data[1])
                    ListTile(
                      key: ValueKey(master['id']),
                      title: Text(master['name'] as String),
                      subtitle: Text(_hoursSummary(context, master)),
                      onTap:
                          canManage ? () => _editHours(context, master) : null,
                      trailing: Switch(
                        value: master['active'] as bool,
                        onChanged: (value) => guard(() async {
                          await api.setMasterActive(
                              _id, master['id'] as String, value);
                        }),
                      ),
                    ),
                ]);
              },
            ),
          ],
        ),
      );

  String _hoursSummary(BuildContext context, Map<String, dynamic> master) {
    final hours =
        (master['hours'] as List<dynamic>).cast<Map<String, dynamic>>();
    if (hours.isEmpty) {
      return _t(
          context, 'Нет рабочих дней', 'Жұмыс күндері жоқ', 'No working days');
    }
    final first = hours.first;
    return '${hours.length} ${_t(context, 'дн.', 'күн', 'days')} · ${first['from']}–${first['to']}'
        '${canManage ? ' ✎' : ''}';
  }
}

/// Weekly schedule editor: a working day has a start and an end; an existing break is preserved.
class _HoursDialog extends StatefulWidget {
  const _HoursDialog({required this.hours});
  final List<Map<String, dynamic>> hours;

  @override
  State<_HoursDialog> createState() => _HoursDialogState();
}

class _HoursDialogState extends State<_HoursDialog> {
  // weekday (1-7) -> window; absent means a day off
  late final Map<int, Map<String, dynamic>> _days = {
    for (final h in widget.hours) h['day'] as int: Map<String, dynamic>.of(h),
  };

  String _dayName(BuildContext context, int day) {
    final names = switch (Localizations.localeOf(context).languageCode) {
      'kk' => ['Дс', 'Сс', 'Ср', 'Бс', 'Жм', 'Сб', 'Жс'],
      'en' => ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
      _ => ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'],
    };
    return names[day - 1];
  }

  Future<void> _pick(int day, String field) async {
    final current = (_days[day]![field] as String).split(':');
    final picked = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(
            hour: int.parse(current[0]), minute: int.parse(current[1])));
    if (picked == null) return;
    setState(() => _days[day]![field] =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(_t(context, 'Расписание', 'Кесте', 'Schedule')),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(shrinkWrap: true, children: [
            for (var day = 1; day <= 7; day++)
              Row(children: [
                SizedBox(width: 32, child: Text(_dayName(context, day))),
                Switch(
                  value: _days.containsKey(day),
                  onChanged: (on) => setState(() {
                    if (on) {
                      _days[day] = {'day': day, 'from': '09:00', 'to': '18:00'};
                    } else {
                      _days.remove(day);
                    }
                  }),
                ),
                if (_days.containsKey(day)) ...[
                  TextButton(
                      onPressed: () => _pick(day, 'from'),
                      child: Text(_days[day]!['from'] as String)),
                  const Text('–'),
                  TextButton(
                      onPressed: () => _pick(day, 'to'),
                      child: Text(_days[day]!['to'] as String)),
                ] else
                  Text(_t(context, 'выходной', 'демалыс', 'day off')),
              ]),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_t(context, 'Отмена', 'Бас тарту', 'Cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, [
                    for (final day in _days.keys.toList()..sort())
                      {
                        'day': day,
                        'from': _days[day]!['from'],
                        'to': _days[day]!['to'],
                        if (_days[day]!['breakFrom'] != null)
                          'breakFrom': _days[day]!['breakFrom'],
                        if (_days[day]!['breakTo'] != null)
                          'breakTo': _days[day]!['breakTo'],
                      },
                  ]),
              child: Text(_t(context, 'Сохранить', 'Сақтау', 'Save'))),
        ],
      );
}

/// «Reply by HH:mm» for a new order; turns into a reminder once the reminder time (D-05: 2 minutes) has passed.
class _RespondBy extends StatelessWidget {
  const _RespondBy({required this.entry});
  final Map<String, dynamic> entry;

  @override
  Widget build(BuildContext context) {
    final by = DateTime.parse(entry['respondBy'] as String).toLocal();
    final reminder = DateTime.parse(entry['reminderAt'] as String).toLocal();
    final late = !DateTime.now().isBefore(reminder);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
          '${late ? '⏰ ' : ''}${_t(context, 'Ответить до', 'Жауап беру мерзімі', 'Reply by')} ${formatClock(by)}',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: late ? Theme.of(context).colorScheme.error : null)),
    );
  }
}
