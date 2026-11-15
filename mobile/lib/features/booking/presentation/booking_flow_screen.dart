import 'package:flutter/material.dart';

import '../../food/data/food_models.dart' show toneColors;
import '../../food/presentation/food_widgets.dart';
import '../booking_services.dart';
import '../data/booking_api.dart';
import '../data/booking_models.dart';
import 'booking_detail_screen.dart';

/// Booking flow for one service: master (or any) → date → free slot → confirmation.
class BookingFlowScreen extends StatefulWidget {
  const BookingFlowScreen(
      {required this.services,
      required this.detail,
      required this.service,
      super.key});

  final BookingServices services;
  final VenueDetail detail;
  final BookableService service;

  @override
  State<BookingFlowScreen> createState() => _BookingFlowScreenState();
}

class _BookingFlowScreenState extends State<BookingFlowScreen> {
  static const _days = 14;

  /// Today in Almaty (UTC+5, no DST), independent of the phone's zone.
  late final DateTime _today = () {
    final now = DateTime.now().toUtc().add(const Duration(hours: 5));
    return DateTime(now.year, now.month, now.day);
  }();

  String? _masterId; // null = any master
  late DateTime _date = _today;
  Future<List<BookingSlot>>? _slots;
  BookingSlot? _slot;
  final _comment = TextEditingController();
  bool _busy = false;
  String? _error;
  String _key = BookingApi.newIdempotencyKey();

  List<BookingMaster> get _masters =>
      widget.detail.mastersFor(widget.service.id);

  @override
  void initState() {
    super.initState();
    _loadSlots();
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  void _loadSlots() {
    _slot = null;
    _slots = widget.services.api.slots(
        venueId: widget.detail.venue.id,
        serviceId: widget.service.id,
        masterId: _masterId,
        date: _date);
  }

  Future<void> _submit() async {
    final slot = _slot;
    if (slot == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final nav = Navigator.of(context);
    try {
      final record = await widget.services.api.book(
        venueId: widget.detail.venue.id,
        serviceId: widget.service.id,
        masterId: slot.masterId,
        startsAtIso: slot.startsAtIso,
        comment: _comment.text,
        idempotencyKey: _key,
      );
      // Back to the app root, then show the new booking on top.
      nav.popUntil((route) => route.isFirst);
      nav.push(MaterialPageRoute<void>(
          builder: (_) => BookingDetailScreen(
              services: widget.services,
              bookingId: record.id,
              initial: record,
              justBooked: true)));
    } on BookingException catch (error) {
      if (!mounted) return;
      // A network failure may have reached the server: keep the key so a retry cannot create a second booking.
      if (error.failure != BookingFailure.offline) {
        _key = BookingApi.newIdempotencyKey();
      }
      setState(() {
        _busy = false;
        _error = error.message;
        if (error.failure == BookingFailure.slotTaken) _loadSlots();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final service = widget.service;
    return Scaffold(
      appBar: AppBar(title: const Text('Запись')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Text(widget.detail.venue.name,
                    style: theme.textTheme.titleMedium),
                Text(
                    '${service.name} · ${formatDuration(service.durationMinutes)} · ${formatTenge(service.priceMinor)}',
                    style: theme.textTheme.titleLarge),
                const SizedBox(height: 20),
                Text('Мастер', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  ChoiceChip(
                    label: const Text('Любой мастер'),
                    selected: _masterId == null,
                    onSelected: _busy
                        ? null
                        : (_) => setState(() {
                              _masterId = null;
                              _loadSlots();
                            }),
                  ),
                  for (final m in _masters)
                    ChoiceChip(
                      avatar: Text(m.emoji),
                      label: Text(m.name),
                      selected: _masterId == m.id,
                      onSelected: _busy
                          ? null
                          : (_) => setState(() {
                                _masterId = m.id;
                                _loadSlots();
                              }),
                    ),
                ]),
                const SizedBox(height: 20),
                Text('Дата', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                SizedBox(
                  height: 64,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _days,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final day = _today.add(Duration(days: i));
                      final selected = day == _date;
                      final label = formatDay(day).split(',');
                      return ChoiceChip(
                        selected: selected,
                        label: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(label.first.toUpperCase(),
                                  style: const TextStyle(fontSize: 11)),
                              Text('${day.day}',
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700)),
                            ]),
                        onSelected: _busy
                            ? null
                            : (_) => setState(() {
                                  _date = day;
                                  _loadSlots();
                                }),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),
                Text('Время · ${formatDay(_date)}',
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                FutureBuilder<List<BookingSlot>>(
                  future: _slots,
                  builder: (context, state) {
                    if (state.connectionState != ConnectionState.done) {
                      return Wrap(spacing: 8, runSpacing: 8, children: [
                        for (var i = 0; i < 8; i++)
                          const SkeletonBox(height: 40, width: 76, radius: 20),
                      ]);
                    }
                    if (state.hasError) {
                      final error = state.error;
                      return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(error is BookingException
                                ? error.message
                                : 'Не удалось загрузить время.'),
                            TextButton(
                                onPressed: () => setState(_loadSlots),
                                child: const Text('Повторить')),
                          ]);
                    }
                    final slots = state.data!;
                    if (slots.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                            'На эту дату нет свободного времени. Выберите другой день или мастера.'),
                      );
                    }
                    return Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final s in slots)
                        ChoiceChip(
                          label: Text(formatClock(s.start)),
                          selected: _slot?.startsAtIso == s.startsAtIso,
                          onSelected:
                              _busy ? null : (_) => setState(() => _slot = s),
                        ),
                    ]);
                  },
                ),
                if (_slot != null) ...[
                  const SizedBox(height: 24),
                  Card(
                    margin: EdgeInsets.zero,
                    color: toneColors('blue').background,
                    elevation: 0,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Ваша запись',
                                style: theme.textTheme.titleMedium),
                            const SizedBox(height: 6),
                            Text(
                                '${formatDay(_slot!.start)}, ${formatClock(_slot!.start)}',
                                style: theme.textTheme.titleLarge),
                            Text('Мастер: ${_slot!.masterName}'),
                            Text(
                                '${service.name} · ${formatDuration(service.durationMinutes)}'),
                            Text(
                                'Стоимость: ${formatTenge(service.priceMinor)} (оплата на месте)'),
                          ]),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _comment,
                    enabled: !_busy,
                    maxLength: 300,
                    decoration: const InputDecoration(
                        labelText: 'Комментарий (необязательно)',
                        hintText: 'Например: фейд, 3 мм',
                        border: OutlineInputBorder()),
                  ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Semantics(
                        liveRegion: true,
                        child: Text(_error!,
                            style: TextStyle(color: theme.colorScheme.error))),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy || _slot == null ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5))
                      : Text(_slot == null
                          ? 'Выберите время'
                          : 'Записаться · ${formatTenge(service.priceMinor)}'),
                ),
                const SizedBox(height: 8),
                Text(
                    'DEV-режим: запись подтверждается автоматически, мастер уведомление не получает. Бесплатная отмена до начала услуги.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ]),
        ),
      ),
    );
  }
}
