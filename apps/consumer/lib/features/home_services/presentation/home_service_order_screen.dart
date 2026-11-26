import 'dart:math';

import 'package:flutter/material.dart';

import 'package:kunde_api/booking_api.dart';
import 'package:kunde_api/home_services_api.dart';
import 'package:kunde_models/booking_models.dart';
import 'package:kunde_ui/ride_strings.dart';

import '../../booking/booking_services.dart';
import '../../booking/presentation/booking_detail_screen.dart';
import 'home_services_offers_screen.dart' show formatKzt;

/// Order of one published offer: date → slot → address → itemised server price → booking. The price the customer saw
/// (`expectedPriceMinor`) is checked by the server again, so a changed tariff can never be charged silently.
class HomeServiceOrderScreen extends StatefulWidget {
  const HomeServiceOrderScreen(
      {required this.offer,
      required this.services,
      required this.api,
      this.initialAreaSqm,
      this.initialUrgent = false,
      super.key});

  /// What the customer already entered on the offer card, so the price they saw is the price they order.
  final int? initialAreaSqm;
  final bool initialUrgent;

  final HomeServiceOffer offer;
  final BookingServices services;
  final HomeServicesCatalog api;

  @override
  State<HomeServiceOrderScreen> createState() => _HomeServiceOrderScreenState();
}

class _HomeServiceOrderScreenState extends State<HomeServiceOrderScreen> {
  final _address = TextEditingController();
  late final _area =
      TextEditingController(text: widget.initialAreaSqm?.toString() ?? '');
  final _comment = TextEditingController();
  final String _key = _newKey();
  late final DateTime _today = DateTime.now();
  late DateTime _date = _today;
  late Future<List<BookingSlot>> _slots = _loadSlots();
  BookingSlot? _slot;
  late bool _urgent = widget.initialUrgent;
  bool _touched = false;
  bool _busy = false;
  String? _error;
  Future<HomeServiceQuote>? _quote;

  static String _newKey() {
    final r = Random.secure();
    return List.generate(
        16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  bool get _perSqm => widget.offer.areaBased;
  int? get _areaValue => int.tryParse(_area.text.trim());
  bool get _addressOk => _address.text.trim().length >= 5;

  Future<List<BookingSlot>> _loadSlots() => widget.services.api.slots(
      venueId: widget.offer.venueId,
      serviceId: widget.offer.serviceId,
      date: _date);

  void _requote() {
    final slot = _slot;
    _quote = slot == null
        ? null
        : widget.api.quote(widget.offer.id,
            areaSqm: _perSqm ? _areaValue : null,
            startsAtIso: slot.startsAtIso,
            urgent: _urgent);
  }

  @override
  void dispose() {
    _address.dispose();
    _area.dispose();
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit(HomeServiceQuote quote) async {
    setState(() => _touched = true);
    final slot = _slot;
    if (slot == null || !_addressOk || (_perSqm && _areaValue == null)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final nav = Navigator.of(context);
    final s = RideStrings(context);
    try {
      final record = await widget.services.api.book(
        venueId: widget.offer.venueId,
        serviceId: widget.offer.serviceId,
        masterId: slot.masterId,
        startsAtIso: slot.startsAtIso,
        comment: _comment.text,
        addressText: _address.text,
        areaSqm: _perSqm ? _areaValue : null,
        idempotencyKey: _key,
        expectedPriceMinor: quote.totalMinor,
        urgent: _urgent,
      );
      if (!mounted) return;
      nav.popUntil((route) => route.isFirst);
      nav.push(MaterialPageRoute<void>(
          builder: (_) => BookingDetailScreen(
              services: widget.services,
              bookingId: record.id,
              initial: record,
              justBooked: true)));
    } on BookingException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = switch (e.failure) {
          BookingFailure.priceChanged => s.t(
              'Цена изменилась. Проверьте сумму и подтвердите снова.',
              'Баға өзгерді. Соманы тексеріп, қайта растаңыз.',
              'The price changed. Check the amount and confirm again.'),
          BookingFailure.slotTaken => s.t(
              'Это время только что заняли. Выберите другое.',
              'Бұл уақытты жаңа ғана алды. Басқасын таңдаңыз.',
              'That time was just taken. Pick another.'),
          _ => s.error,
        };
        if (e.failure == BookingFailure.priceChanged) _requote();
        if (e.failure == BookingFailure.slotTaken) {
          _slot = null;
          _slots = _loadSlots();
          _quote = null;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    final theme = Theme.of(context);
    final days = [for (var i = 0; i < 7; i++) _today.add(Duration(days: i))];
    return Scaffold(
      appBar: AppBar(
          title: Text(
              s.t('Оформление заказа', 'Тапсырысты рәсімдеу', 'Place order'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Text(widget.offer.name(s.language),
                style: theme.textTheme.titleLarge),
            Text(widget.offer.venueName),
            const SizedBox(height: 16),
            Text(s.t('Дата', 'Күні', 'Date'),
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            SizedBox(
              height: 48,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final d in days)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      key: ValueKey('day-${d.month}-${d.day}'),
                      label: Text(
                          '${d.day}.${d.month.toString().padLeft(2, '0')}'),
                      selected: d.day == _date.day && d.month == _date.month,
                      onSelected: (_) => setState(() {
                        _date = d;
                        _slot = null;
                        _quote = null;
                        _slots = _loadSlots();
                      }),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 12),
            Text(s.t('Время', 'Уақыт', 'Time'),
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            FutureBuilder<List<BookingSlot>>(
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
                // One entry per start time: the server picks the master by the slot it is given.
                final seen = <String>{};
                final unique =
                    slots.where((x) => seen.add(x.startsAtIso)).toList();
                return Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final slot in unique)
                    ChoiceChip(
                      key: ValueKey('slot-${slot.startsAtIso}'),
                      label: Text(
                          '${slot.start.hour.toString().padLeft(2, '0')}:${slot.start.minute.toString().padLeft(2, '0')}'),
                      selected: _slot?.startsAtIso == slot.startsAtIso,
                      onSelected: (_) => setState(() {
                        _slot = slot;
                        _requote();
                      }),
                    ),
                ]);
              },
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('address'),
              controller: _address,
              decoration: InputDecoration(
                labelText: s.t('Адрес', 'Мекенжай', 'Address'),
                errorText: _touched && !_addressOk
                    ? s.t(
                        'Укажите адрес (от 5 символов)',
                        'Мекенжайды көрсетіңіз (кемінде 5 таңба)',
                        'Enter an address (5+ characters)')
                    : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (_perSqm)
              TextField(
                key: const ValueKey('area'),
                controller: _area,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                    labelText: s.t('Площадь, м²', 'Ауданы, м²', 'Area, m²'),
                    errorText: _touched && _areaValue == null
                        ? s.t('Укажите площадь', 'Ауданын көрсетіңіз',
                            'Enter the area')
                        : null),
                onChanged: (_) => setState(_requote),
              ),
            TextField(
              controller: _comment,
              maxLines: 2,
              decoration: InputDecoration(
                  labelText: s.t('Комментарий', 'Түсініктеме', 'Comment')),
            ),
            SwitchListTile(
              key: const ValueKey('urgent'),
              contentPadding: EdgeInsets.zero,
              title: Text(s.t('Срочно', 'Шұғыл', 'Urgent')),
              value: _urgent,
              onChanged: (v) => setState(() {
                _urgent = v;
                _requote();
              }),
            ),
            FutureBuilder<HomeServiceQuote>(
              future: _quote,
              builder: (context, state) {
                if (_quote == null) {
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.t(
                            'Выберите время, чтобы увидеть цену',
                            'Бағаны көру үшін уақытты таңдаңыз',
                            'Pick a time to see the price')),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(_error!,
                                style:
                                    TextStyle(color: theme.colorScheme.error)),
                          ),
                      ]);
                }
                if (state.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state.hasError) return Text(s.error);
                final q = state.data!;
                Widget row(String label, int minor, {bool bold = false}) =>
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(children: [
                        Expanded(child: Text(label)),
                        Text(formatKzt(minor),
                            style: bold ? theme.textTheme.titleMedium : null),
                      ]),
                    );
                return Column(children: [
                  row(s.t('Услуга', 'Қызмет', 'Service'), q.listPriceMinor),
                  if (q.callOutFeeMinor > 0)
                    row(s.t('Выезд', 'Шығу', 'Call-out'), q.callOutFeeMinor),
                  if (q.urgentSurchargeMinor > 0)
                    row(s.t('Срочность', 'Шұғылдық', 'Urgency'),
                        q.urgentSurchargeMinor),
                  if (q.eveningSurchargeMinor > 0)
                    row(s.t('Вечернее время', 'Кешкі уақыт', 'Evening'),
                        q.eveningSurchargeMinor),
                  const Divider(),
                  row(s.t('Итого', 'Барлығы', 'Total'), q.totalMinor,
                      bold: true),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_error!,
                          style: TextStyle(color: theme.colorScheme.error)),
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const ValueKey('submit'),
                    onPressed: _busy ? null : () => _submit(q),
                    child: Text(s.t(
                        'Заказать за ${formatKzt(q.totalMinor)}',
                        '${formatKzt(q.totalMinor)} тапсырыс беру',
                        'Order for ${formatKzt(q.totalMinor)}')),
                  ),
                ]);
              },
            ),
          ]),
        ),
      ),
    );
  }
}
