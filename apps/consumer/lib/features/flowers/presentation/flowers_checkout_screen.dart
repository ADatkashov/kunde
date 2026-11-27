import 'dart:math';

import 'package:flutter/material.dart';
import 'package:kunde_ui/ride_strings.dart';

import '../data/flowers_models.dart';
import '../data/flowers_orders_api.dart';
import '../data/flowers_services.dart';
import 'flowers_order_screen.dart';
import 'flowers_widgets.dart';

/// «Доставка»: as soon as possible or a two-hour window of a chosen day, address, recipient and card text, then the order.
/// The total shown is the server quote and is sent back as `expectedTotalMinor`, so a changed price is never charged silently.
class FlowersCheckoutScreen extends StatefulWidget {
  const FlowersCheckoutScreen({required this.services, super.key});

  final FlowersServices services;

  @override
  State<FlowersCheckoutScreen> createState() => _FlowersCheckoutScreenState();
}

class _FlowersCheckoutScreenState extends State<FlowersCheckoutScreen> {
  final _address = TextEditingController();
  final _recipient = TextEditingController();
  final _card = TextEditingController();
  final _comment = TextEditingController();
  final String _key = _newKey();
  late final DateTime _today = DateTime.now();
  late DateTime _day = DateTime(_today.year, _today.month, _today.day);
  String _mode = 'ASAP';
  Future<List<FlowersSlot>>? _slots;
  FlowersSlot? _slot;
  Future<FlowersQuote>? _quote;
  bool _touched = false;
  bool _busy = false;
  String? _error;

  static String _newKey() {
    final r = Random.secure();
    return List.generate(
        16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  bool get _addressOk => _address.text.trim().length >= 5;

  @override
  void initState() {
    super.initState();
    _requote();
  }

  @override
  void dispose() {
    _address.dispose();
    _recipient.dispose();
    _card.dispose();
    _comment.dispose();
    super.dispose();
  }

  String _dateParam(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<List<FlowersSlot>> _loadSlots() async => [
        for (final s in await widget.services.api.flowersJson(
            'delivery-slots', {'date': _dateParam(_day)}) as List<dynamic>)
          FlowersSlot.fromJson(s as Map<String, dynamic>),
      ];

  void _requote() {
    final cart = widget.services.cart;
    final orders = widget.services.orders;
    if (orders == null || cart.shopId == null) return;
    if (_mode == 'SCHEDULED' && _slot == null) {
      _quote = null;
      return;
    }
    final future = orders.quote(
        shopId: cart.shopId!,
        items: cart.toRequestItems(),
        deliveryMode: _mode,
        scheduledFromIso: _mode == 'SCHEDULED' ? _slot!.startsAtIso : null);
    _quote = future;
  }

  String _explain(RideStrings s, FlowersFailure f) => switch (f) {
        FlowersFailure.priceChanged => s.t(
            'Цена изменилась. Проверьте сумму и подтвердите снова.',
            'Баға өзгерді. Соманы тексеріп, қайта растаңыз.',
            'The price changed. Check the amount and confirm again.'),
        FlowersFailure.stock => s.t(
            'Товара не хватает в наличии. Измените корзину.',
            'Тауар жеткіліксіз. Себетті өзгертіңіз.',
            'Not enough in stock. Change the cart.'),
        FlowersFailure.slot => s.t(
            'Это время недоступно. Выберите другое.',
            'Бұл уақыт қолжетімсіз. Басқасын таңдаңыз.',
            'That time is unavailable. Pick another.'),
        FlowersFailure.shopClosed => s.t(
            'Магазин закрыт. Выберите время доставки.',
            'Дүкен жабық. Жеткізу уақытын таңдаңыз.',
            'The shop is closed. Pick a delivery time.'),
        FlowersFailure.signedOut => s.t('Войдите, чтобы оформить заказ.',
            'Тапсырыс беру үшін кіріңіз.', 'Sign in to place an order.'),
        _ => s.error,
      };

  Future<void> _submit(FlowersQuote quote) async {
    setState(() => _touched = true);
    final orders = widget.services.orders;
    final cart = widget.services.cart;
    if (orders == null || cart.shopId == null || !_addressOk) return;
    if (_mode == 'SCHEDULED' && _slot == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final nav = Navigator.of(context);
    final s = RideStrings(context);
    try {
      final order = await orders.place(
        idempotencyKey: _key,
        shopId: cart.shopId!,
        items: cart.toRequestItems(),
        deliveryMode: _mode,
        scheduledFromIso: _mode == 'SCHEDULED' ? _slot!.startsAtIso : null,
        addressText: _address.text.trim(),
        recipientName: _recipient.text.trim(),
        cardText: _card.text.trim(),
        comment: _comment.text.trim(),
        expectedTotalMinor: quote.totalMinor,
      );
      cart.clear();
      if (!mounted) return;
      nav.popUntil(
          (route) => route.isFirst || route.settings.name == '/flowers');
      nav.push(MaterialPageRoute<void>(
          builder: (_) => FlowersOrderScreen(
              services: widget.services, initial: order, justPlaced: true)));
    } on FlowersException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _explain(s, e.failure);
        if (e.failure == FlowersFailure.priceChanged ||
            e.failure == FlowersFailure.slot) {
          _slot = e.failure == FlowersFailure.slot ? null : _slot;
          if (e.failure == FlowersFailure.slot) _slots = _loadSlots();
          _requote();
        }
      });
    }
  }

  Widget _modeCard(String mode, String title, String? caption,
      {String? badge}) {
    final colors = Theme.of(context).colorScheme;
    final selected = _mode == mode;
    return Material(
      color: selected
          ? colors.primaryContainer.withValues(alpha: .45)
          : colors.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
              color: selected ? colors.primary : colors.outlineVariant,
              width: selected ? 2 : 1)),
      child: InkWell(
        key: ValueKey('mode-$mode'),
        borderRadius: BorderRadius.circular(20),
        onTap: () => setState(() {
          _mode = mode;
          if (mode == 'SCHEDULED') _slots ??= _loadSlots();
          _requote();
        }),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: colors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    if (caption != null)
                      Text(caption,
                          style: TextStyle(color: colors.onSurfaceVariant)),
                  ]),
            ),
            if (badge != null) FlowersPill(badge),
          ]),
        ),
      ),
    );
  }

  Widget _scheduled(RideStrings s) {
    final first = DateTime(_today.year, _today.month, _today.day);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      CalendarDatePicker(
        key: const ValueKey('calendar'),
        initialDate: _day,
        firstDate: first,
        lastDate: first.add(const Duration(days: 14)),
        onDateChanged: (d) => setState(() {
          _day = DateTime(d.year, d.month, d.day);
          _slot = null;
          _slots = _loadSlots();
          _requote();
        }),
      ),
      Text(s.t('Выберите время', 'Уақытты таңдаңыз', 'Pick a time'),
          style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      FutureBuilder<List<FlowersSlot>>(
        future: _slots,
        builder: (context, state) {
          if (state.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.hasError) return Text(s.error);
          final slots = state.data!;
          if (slots.isEmpty) {
            return Text(s.t('На эту дату нет свободного времени',
                'Бұл күні бос уақыт жоқ', 'No free time on this date'));
          }
          String hm(DateTime d) {
            final l = d.toLocal();
            return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
          }

          return Wrap(spacing: 8, runSpacing: 8, children: [
            for (final slot in slots)
              ChoiceChip(
                key: ValueKey('slot-${slot.startsAtIso}'),
                shape: const StadiumBorder(),
                showCheckmark: false,
                label: Text('${hm(slot.startsAt)}–${hm(slot.endsAt)}'),
                selected: _slot?.startsAtIso == slot.startsAtIso,
                onSelected: (_) => setState(() {
                  _slot = slot;
                  _requote();
                }),
              ),
          ]);
        },
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    final theme = Theme.of(context);
    final cart = widget.services.cart;
    return Scaffold(
      appBar: AppBar(
          centerTitle: true,
          title: Text(s.t('Доставка', 'Жеткізу', 'Delivery'),
              style: const TextStyle(fontWeight: FontWeight.w800))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            _modeCard(
                'ASAP',
                s.t('Как можно скорее', 'Мүмкіндігінше тез',
                    'As soon as possible'),
                null,
                badge: s.t('Быстро', 'Жылдам', 'Fast')),
            const SizedBox(height: 10),
            _modeCard(
                'SCHEDULED',
                s.t('К определённому времени', 'Белгілі уақытқа',
                    'At a chosen time'),
                null),
            if (_mode == 'SCHEDULED') ...[
              const SizedBox(height: 8),
              _scheduled(s)
            ],
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('address'),
              controller: _address,
              decoration: InputDecoration(
                labelText: s.t(
                    'Адрес доставки', 'Жеткізу мекенжайы', 'Delivery address'),
                hintText: s.t('Улица, дом, квартира', 'Көше, үй, пәтер',
                    'Street, building, apartment'),
                errorText: _touched && !_addressOk
                    ? s.t(
                        'Укажите адрес (от 5 символов)',
                        'Мекенжайды көрсетіңіз (кемінде 5 таңба)',
                        'Enter an address (5+ characters)')
                    : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _recipient,
              decoration: InputDecoration(
                  labelText:
                      s.t('Имя получателя', 'Алушының аты', 'Recipient name')),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _card,
              maxLines: 2,
              maxLength: 300,
              decoration: InputDecoration(
                  labelText:
                      s.t('Текст открытки', 'Ашықхат мәтіні', 'Card text')),
            ),
            TextField(
              controller: _comment,
              maxLines: 2,
              decoration: InputDecoration(
                  labelText: s.t('Комментарий', 'Түсініктеме', 'Comment'),
                  hintText: s.t(
                      'Например: позвонить за 10 минут',
                      'Мысалы: 10 минут бұрын қоңырау шалыңыз',
                      'For example: call 10 minutes before')),
            ),
            const SizedBox(height: 16),
            FutureBuilder<FlowersQuote>(
              future: _quote,
              builder: (context, state) {
                if (_quote == null) {
                  return Text(s.t(
                      'Выберите время, чтобы увидеть сумму',
                      'Соманы көру үшін уақытты таңдаңыз',
                      'Pick a time to see the total'));
                }
                if (state.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state.hasError) {
                  final failure = state.error is FlowersException
                      ? (state.error as FlowersException).failure
                      : FlowersFailure.other;
                  return Text(_explain(s, failure),
                      style: TextStyle(color: theme.colorScheme.error));
                }
                final q = state.data!;
                Widget row(String label, String value) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(children: [
                        Expanded(child: Text(label)),
                        Text(value)
                      ]),
                    );
                return Column(children: [
                  row(s.t('Товары', 'Тауарлар', 'Items'),
                      formatKzt(q.subtotalMinor)),
                  row(
                      s.t('Доставка', 'Жеткізу', 'Delivery'),
                      q.deliveryFeeMinor == 0
                          ? s.t('Бесплатно', 'Тегін', 'Free')
                          : formatKzt(q.deliveryFeeMinor)),
                  const Divider(height: 24),
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Expanded(
                        child: Text(s.t('Итого', 'Барлығы', 'Total'),
                            style: theme.textTheme.titleLarge)),
                    Text(formatKzt(q.totalMinor),
                        style: theme.textTheme.headlineSmall),
                  ]),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_error!,
                          style: TextStyle(color: theme.colorScheme.error)),
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const ValueKey('submit'),
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                        shape: const StadiumBorder()),
                    onPressed: _busy || widget.services.orders == null
                        ? null
                        : () => _submit(q),
                    child: Text(widget.services.orders == null
                        ? s.t('Войдите, чтобы заказать',
                            'Тапсырыс беру үшін кіріңіз', 'Sign in to order')
                        : s.t('Продолжить', 'Жалғастыру', 'Continue')),
                  ),
                ]);
              },
            ),
            if (cart.isEmpty) const SizedBox.shrink(),
          ]),
        ),
      ),
    );
  }
}
