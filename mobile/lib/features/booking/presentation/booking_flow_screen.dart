import 'package:flutter/material.dart';

import 'package:kunde_ui/booking_strings.dart';

import 'package:kunde_models/food_models.dart' show toneColors;
import '../../food/presentation/food_widgets.dart';
import '../booking_services.dart';
import 'package:kunde_api/booking_api.dart';
import 'package:kunde_models/booking_models.dart';
import 'booking_detail_screen.dart';

/// Booking flow for one service: master (or any) → date → free slot → confirmation.
class BookingFlowScreen extends StatefulWidget {
  const BookingFlowScreen({
    required this.services,
    required this.detail,
    required this.service,
    this.initialMasterId,
    super.key,
  });

  final BookingServices services;
  final VenueDetail detail;
  final BookableService service;
  final String? initialMasterId;

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

  late String? _masterId = widget.initialMasterId; // null = any master
  late DateTime _date = _today;
  Future<List<BookingSlot>>? _slots;
  BookingSlot? _slot;
  final _comment = TextEditingController();
  bool _busy = false;
  bool _acceptsTerms = false;
  bool _uncertain = false;
  String _paymentMethod = 'PAY_ON_SITE';

  bool get _health => widget.detail.venue.category == 'HEALTH';
  bool get _selectionLocked => _busy || (_health && _uncertain);
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
      date: _date,
    );
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
        comment: _health ? null : _comment.text,
        expectedPriceMinor: _health ? widget.service.priceMinor : null,
        paymentMethod: _health ? _paymentMethod : null,
        acceptsTerms: _health ? _acceptsTerms : null,
        idempotencyKey: _key,
      );
      if (!mounted) return;
      // Back to the app root, then show the new booking on top.
      nav.popUntil((route) => route.isFirst);
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => BookingDetailScreen(
            services: widget.services,
            bookingId: record.id,
            initial: record,
            justBooked: true,
          ),
        ),
      );
    } on BookingException catch (error) {
      if (!mounted) return;
      // A network failure may have reached the server: keep the key so a retry cannot create a second booking.
      if (error.failure != BookingFailure.offline) {
        _key = BookingApi.newIdempotencyKey();
      }
      setState(() {
        _busy = false;
        _uncertain = error.failure == BookingFailure.offline;
        _error = bkL10n(context).bkError(error.failure);
        if (error.failure == BookingFailure.slotTaken) _loadSlots();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = bkL10n(context);
    final service = widget.service;
    final material = MaterialLocalizations.of(context);
    String dateLabel(DateTime date) =>
        _health ? material.formatMediumDate(date) : formatDay(date);
    return Scaffold(
      appBar: AppBar(title: Text(s.bkBookingTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Text(
                widget.detail.venue.name,
                style: theme.textTheme.titleMedium,
              ),
              Text(
                '${s.bkCatalogName(service.name)} · ${formatDuration(service.durationMinutes)} · ${formatTenge(service.priceMinor)}',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 20),
              Text(_health ? s.healthSpecialist : s.bkMaster,
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label:
                        Text(_health ? s.anyHealthSpecialist : s.bkAnyMaster),
                    selected: _masterId == null,
                    onSelected: _selectionLocked
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
                      onSelected: _selectionLocked
                          ? null
                          : (_) => setState(() {
                                _masterId = m.id;
                                _loadSlots();
                              }),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Text(s.bkDate, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              SizedBox(
                height: _health
                    ? 36 + MediaQuery.textScalerOf(context).scale(28)
                    : 64,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _days,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final day = _today.add(Duration(days: i));
                    final selected = day == _date;
                    final label = dateLabel(day).split(',');
                    return Semantics(
                      identifier: _health ? 'health-day-$i' : null,
                      child: ChoiceChip(
                        selected: selected,
                        label: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              label.first.toUpperCase(),
                              style: const TextStyle(fontSize: 11),
                            ),
                            Text(
                              '${day.day}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        onSelected: _selectionLocked
                            ? null
                            : (_) => setState(() {
                                  _date = day;
                                  _loadSlots();
                                }),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '${s.bkTime} · ${dateLabel(_date)}',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              FutureBuilder<List<BookingSlot>>(
                future: _slots,
                builder: (context, state) {
                  if (state.connectionState != ConnectionState.done) {
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var i = 0; i < 8; i++)
                          const SkeletonBox(height: 40, width: 76, radius: 20),
                      ],
                    );
                  }
                  if (state.hasError) {
                    final error = state.error;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          error is BookingException
                              ? s.bkError(error.failure)
                              : s.bkSlotsError,
                        ),
                        TextButton(
                          onPressed: () => setState(_loadSlots),
                          child: Text(s.bkRetry),
                        ),
                      ],
                    );
                  }
                  final slots = state.data!;
                  if (slots.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(s.bkNoSlots),
                    );
                  }
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s in slots)
                        ChoiceChip(
                          label: Text(formatClock(s.start)),
                          selected: _slot?.startsAtIso == s.startsAtIso,
                          onSelected: _selectionLocked
                              ? null
                              : (_) => setState(() => _slot = s),
                        ),
                    ],
                  );
                },
              ),
              if (_slot != null) ...[
                const SizedBox(height: 24),
                Card(
                  margin: EdgeInsets.zero,
                  color: _health
                      ? theme.colorScheme.surfaceContainerHighest
                      : toneColors('blue').background,
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.bkYourBooking,
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${dateLabel(_slot!.start)}, ${formatClock(_slot!.start)}',
                          style: theme.textTheme.titleLarge,
                        ),
                        Text(_health
                            ? s.healthSpecialistLine(_slot!.masterName)
                            : s.bkMasterLine(_slot!.masterName)),
                        Text(
                          '${s.bkCatalogName(service.name)} · ${formatDuration(service.durationMinutes)}',
                        ),
                        Text(
                          _health
                              ? formatTenge(service.priceMinor)
                              : s.bkCostOnSite(formatTenge(service.priceMinor)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_health) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final (method, label) in [
                        (
                          'PAY_ON_SITE',
                          s.healthText(
                            'Оплата на месте',
                            'Орнында төлеу',
                            'Pay on site',
                          ),
                        ),
                        (
                          'TEST_CARD',
                          s.healthText(
                            'Тестовая карта',
                            'Сынақ картасы',
                            'Test card',
                          ),
                        ),
                      ])
                        ChoiceChip(
                          label: Text(label),
                          selected: _paymentMethod == method,
                          onSelected: _selectionLocked
                              ? null
                              : (selected) {
                                  if (selected) {
                                    setState(() => _paymentMethod = method);
                                  }
                                },
                        ),
                    ],
                  ),
                  if (_paymentMethod == 'TEST_CARD')
                    Text(
                      s.healthText(
                        'Тестовый платёж без списания',
                        'Ақша алынбайтын сынақ төлемі',
                        'Test payment without a charge',
                      ),
                    ),
                  Semantics(
                    identifier: 'health-terms',
                    child: CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _acceptsTerms,
                      onChanged: _selectionLocked
                          ? null
                          : (value) =>
                              setState(() => _acceptsTerms = value ?? false),
                      title: Text(
                        s.healthText(
                          'Согласен с ценой и условиями записи',
                          'Баға мен жазылу шарттарына келісемін',
                          'I accept the price and booking terms',
                        ),
                      ),
                      subtitle: Text(
                        s.healthText(
                          'Демо-запись можно отменить до её начала.',
                          'Демо жазбадан ол басталғанға дейін бас тартуға болады.',
                          'A demo appointment can be cancelled before it starts.',
                        ),
                      ),
                    ),
                  ),
                ] else
                  TextField(
                    controller: _comment,
                    enabled: !_busy,
                    maxLength: 300,
                    decoration: InputDecoration(
                      labelText: s.bkCommentLabel,
                      hintText: s.bkCommentHint,
                      border: const OutlineInputBorder(),
                    ),
                  ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Semantics(
                identifier: _health ? 'health-book-submit' : null,
                child: FilledButton(
                  onPressed:
                      _busy || _slot == null || (_health && !_acceptsTerms)
                          ? null
                          : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : Text(
                          _slot == null
                              ? s.bkPickTime
                              : s.bkConfirmBook(
                                  formatTenge(service.priceMinor),
                                ),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _health
                    ? s.healthText(
                        'Демо-запись в синтетическую организацию',
                        'Синтетикалық ұйымға демо жазылу',
                        'Demo appointment with a synthetic organization')
                    : s.bkFormDevNote,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
