import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kunde_ui/ride_strings.dart';

import '../../home_services/presentation/home_services_widgets.dart'
    show HomeServiceStepper;
import '../data/flowers_models.dart';
import '../data/flowers_orders_api.dart';
import '../data/flowers_services.dart';
import 'flowers_widgets.dart';

/// Step of the four-stage tracker for an order status; `null` for a cancelled order.
int? flowersStep(String status) => switch (status) {
      'PLACED' || 'ACCEPTED' => 0,
      'ASSEMBLING' => 1,
      'ON_THE_WAY' => 2,
      'DELIVERED' => 3,
      _ => null,
    };

String flowersWindowLabel(FlowersOrder o, RideStrings s) {
  final from = o.scheduledFrom;
  final to = o.scheduledTo;
  if (o.deliveryMode != 'SCHEDULED' || from == null || to == null) {
    return s.t('Как можно скорее', 'Мүмкіндігінше тез', 'As soon as possible');
  }
  String hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  return '${from.day.toString().padLeft(2, '0')}.${from.month.toString().padLeft(2, '0')}, ${hm(from)}–${hm(to)}';
}

/// One order: status tracker, delivery window, items and total; free cancellation while the order is only placed.
class FlowersOrderScreen extends StatefulWidget {
  const FlowersOrderScreen(
      {required this.services,
      required this.initial,
      this.justPlaced = false,
      this.every = const Duration(seconds: 15),
      super.key});

  final FlowersServices services;
  final FlowersOrder initial;
  final bool justPlaced;
  final Duration every;

  @override
  State<FlowersOrderScreen> createState() => _FlowersOrderScreenState();
}

class _FlowersOrderScreenState extends State<FlowersOrderScreen> {
  late FlowersOrder _order = widget.initial;
  Timer? _timer;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.every, (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final api = widget.services.orders;
    if (api == null || !_order.active) return;
    try {
      final next = await api.order(_order.id);
      if (mounted) setState(() => _order = next);
    } catch (_) {
      // Keep the last known state.
    }
  }

  Future<void> _cancel() async {
    final api = widget.services.orders;
    if (api == null) return;
    final s = RideStrings(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final next = await api.cancel(_order.id);
      if (mounted) setState(() => _order = next);
    } on FlowersException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.failure == FlowersFailure.notCancellable
            ? s.t(
                'Магазин уже принял заказ. Отмена через поддержку.',
                'Дүкен тапсырысты қабылдады. Тоқтату қолдау арқылы.',
                'The shop has already accepted the order. Cancel through support.')
            : s.error;
      });
      unawaited(_refresh());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    final theme = Theme.of(context);
    final o = _order;
    final step = flowersStep(o.status);
    final short = o.id.length >= 8 ? o.id.substring(0, 8).toUpperCase() : o.id;
    return Scaffold(
      appBar: AppBar(
          centerTitle: true,
          title: Text('${s.t('Заказ', 'Тапсырыс', 'Order')} №$short',
              style: const TextStyle(fontWeight: FontWeight.w800))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            if (widget.justPlaced)
              Card(
                color: theme.colorScheme.primaryContainer,
                child: ListTile(
                  leading: const Icon(Icons.check_circle_rounded),
                  title: Text(s.t(
                      'Заказ принят', 'Тапсырыс қабылданды', 'Order placed')),
                  subtitle: Text(s.t(
                      'Магазин скоро подтвердит заказ.',
                      'Дүкен жақында растайды.',
                      'The shop will confirm it soon.')),
                ),
              ),
            if (step != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: HomeServiceStepper(step: step, labels: [
                  s.t('Принят', 'Қабылданды', 'Placed'),
                  s.t('Собирается', 'Жиналуда', 'Assembling'),
                  s.t('В пути', 'Жолда', 'On the way'),
                  s.t('Доставлен', 'Жеткізілді', 'Delivered'),
                ]),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                    s.t('Заказ отменён', 'Тапсырыс бас тартылды',
                        'Order cancelled'),
                    key: const ValueKey('cancelled'),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: theme.colorScheme.error)),
              ),
            if (o.status == 'ON_THE_WAY' ||
                (o.status == 'ASSEMBLING' && o.courierAssigned))
              Card(
                key: const ValueKey('courier-card'),
                color:
                    theme.colorScheme.primaryContainer.withValues(alpha: .45),
                elevation: 0,
                child: ListTile(
                  leading: Icon(Icons.delivery_dining_rounded,
                      color: theme.colorScheme.primary),
                  title: Text(
                      s.t('Курьер KUNDE', 'KUNDE курьері', 'KUNDE courier'),
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(o.status == 'ON_THE_WAY'
                      ? (o.etaMinutes == null
                          ? s.t('Курьер в пути', 'Курьер жолда',
                              'The courier is on the way')
                          : s.t(
                              'Прибудет через ~${o.etaMinutes} мин',
                              '~${o.etaMinutes} мин ішінде жетеді',
                              'Arriving in ~${o.etaMinutes} min'))
                      : s.t(
                          'Курьер едет в магазин',
                          'Курьер дүкенге бара жатыр',
                          'The courier is heading to the shop')),
                ),
              ),
            Text(o.shopName, style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            _info(
                Icons.schedule_rounded,
                s.t('Доставка', 'Жеткізу', 'Delivery'),
                flowersWindowLabel(o, s)),
            _info(Icons.location_on_rounded,
                s.t('Адрес', 'Мекенжай', 'Address'), o.addressText),
            if ((o.recipientName ?? '').isNotEmpty)
              _info(Icons.person_outline_rounded,
                  s.t('Получатель', 'Алушы', 'Recipient'), o.recipientName!),
            if ((o.cardText ?? '').isNotEmpty)
              _info(Icons.mail_outline_rounded,
                  s.t('Открытка', 'Ашықхат', 'Card'), o.cardText!),
            const Divider(height: 28),
            for (final l in o.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Expanded(child: Text('${l.name} × ${l.quantity}')),
                  Text(formatKzt(l.lineTotalMinor)),
                ]),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Expanded(child: Text(s.t('Доставка', 'Жеткізу', 'Delivery'))),
                Text(o.deliveryFeeMinor == 0
                    ? s.t('Бесплатно', 'Тегін', 'Free')
                    : formatKzt(o.deliveryFeeMinor)),
              ]),
            ),
            const Divider(height: 28),
            Row(children: [
              Expanded(
                  child: Text(s.t('Итого', 'Барлығы', 'Total'),
                      style: theme.textTheme.titleLarge)),
              Text(formatKzt(o.totalMinor),
                  style: theme.textTheme.headlineSmall),
            ]),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!,
                    style: TextStyle(color: theme.colorScheme.error)),
              ),
            if (o.cancellable) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                key: const ValueKey('cancel'),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: const StadiumBorder()),
                onPressed: _busy ? null : _cancel,
                child: Text(s.t(
                    'Отменить заказ', 'Тапсырыстан бас тарту', 'Cancel order')),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _info(IconData icon, String label, String value) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: colors.primary, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
        ),
      ]),
    );
  }
}

/// The caller's flower orders, newest first.
class FlowersOrdersScreen extends StatefulWidget {
  const FlowersOrdersScreen({required this.services, super.key});

  final FlowersServices services;

  @override
  State<FlowersOrdersScreen> createState() => _FlowersOrdersScreenState();
}

class _FlowersOrdersScreenState extends State<FlowersOrdersScreen> {
  late Future<List<FlowersOrder>> _orders = _load();

  Future<List<FlowersOrder>> _load() async => widget.services.orders == null
      ? <FlowersOrder>[]
      : widget.services.orders!.orders();

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    return Scaffold(
      appBar: AppBar(
          centerTitle: true,
          title: Text(s.t('Мои заказы', 'Менің тапсырыстарым', 'My orders'),
              style: const TextStyle(fontWeight: FontWeight.w800))),
      body: FutureBuilder<List<FlowersOrder>>(
        future: _orders,
        builder: (context, state) {
          if (state.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.hasError) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(s.error),
                TextButton(
                    onPressed: () => setState(() => _orders = _load()),
                    child: Text(s.retry)),
              ]),
            );
          }
          final list = state.data!;
          if (list.isEmpty) {
            return Center(
                child: Text(
                    s.t('Заказов пока нет', 'Тапсырыс жоқ', 'No orders yet')));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final o = list[i];
              return Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  key: ValueKey('order-${o.id}'),
                  title: Text(o.shopName,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(flowersWindowLabel(o, s)),
                  trailing: Text(formatKzt(o.totalMinor),
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => FlowersOrderScreen(
                              services: widget.services, initial: o))),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
