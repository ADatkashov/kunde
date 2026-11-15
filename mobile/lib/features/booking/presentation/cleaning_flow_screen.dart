import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../food/data/food_models.dart' show toneColors;
import '../../food/presentation/food_widgets.dart';
import '../booking_services.dart';
import '../data/booking_api.dart';
import '../data/booking_models.dart';
import 'booking_detail_screen.dart';
import 'booking_strings.dart';

/// Home services → Cleaning. Reuses the shared booking mechanism: cleaning type → address → area → estimated price →
/// date and free time → request. Cleaning crews are synthetic in DEV; prices are demo prices, not real offers.
class CleaningFlowScreen extends StatefulWidget {
  const CleaningFlowScreen({required this.services, super.key});

  final BookingServices services;

  @override
  State<CleaningFlowScreen> createState() => _CleaningFlowScreenState();
}

class _CleaningFlowScreenState extends State<CleaningFlowScreen> {
  late Future<VenueDetail?> _detail = _load();

  Future<VenueDetail?> _load() async {
    final venues = await widget.services.api.venues(category: 'CLEANING');
    final open = venues.where((v) => v.open).toList();
    if (open.isEmpty) return null;
    return widget.services.api.venue(open.first.id);
  }

  @override
  Widget build(BuildContext context) {
    final s = bkL10n(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.bkCleaningTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: FutureBuilder<VenueDetail?>(
            future: _detail,
            builder: (context, state) {
              if (state.connectionState != ConnectionState.done) {
                return const RestaurantListSkeleton(count: 3);
              }
              if (state.hasError) {
                final error = state.error;
                return FoodStateMessage(
                    icon: Icons.cloud_off_outlined,
                    title: s.bkCleaningLoadError,
                    body: error is BookingException
                        ? s.bkError(error.failure)
                        : null,
                    onAction: () => setState(() => _detail = _load()));
              }
              final detail = state.data;
              final available = detail?.services
                      .where((x) =>
                          x.available && detail.mastersFor(x.id).isNotEmpty)
                      .toList() ??
                  const <BookableService>[];
              if (detail == null || available.isEmpty) {
                return FoodStateMessage(
                    icon: Icons.cleaning_services_outlined,
                    title: s.bkCleaningNone,
                    body: s.bkNoVenuesBody);
              }
              return _CleaningForm(
                  services: widget.services, detail: detail, types: available);
            },
          ),
        ),
      ),
    );
  }
}

class _CleaningForm extends StatefulWidget {
  const _CleaningForm(
      {required this.services, required this.detail, required this.types});

  final BookingServices services;
  final VenueDetail detail;
  final List<BookableService> types;

  @override
  State<_CleaningForm> createState() => _CleaningFormState();
}

class _CleaningFormState extends State<_CleaningForm> {
  static const _days = 14;

  /// Today in Almaty (UTC+5, no DST), independent of the phone's zone.
  late final DateTime _today = () {
    final now = DateTime.now().toUtc().add(const Duration(hours: 5));
    return DateTime(now.year, now.month, now.day);
  }();

  late BookableService _type = widget.types.first;
  late DateTime _date = _today;
  Future<List<BookingSlot>>? _slots;
  BookingSlot? _slot;
  final _address = TextEditingController();
  final _area = TextEditingController();
  final _comment = TextEditingController();
  bool _touched = false;
  bool _busy = false;
  String? _error;
  String _key = BookingApi.newIdempotencyKey();

  @override
  void initState() {
    super.initState();
    _loadSlots();
  }

  @override
  void dispose() {
    _address.dispose();
    _area.dispose();
    _comment.dispose();
    super.dispose();
  }

  int? get _areaValue => int.tryParse(_area.text.trim());
  bool get _addressOk => _address.text.trim().length >= 5;
  int? get _price => _type.priceFor(_areaValue);

  void _loadSlots() {
    _slot = null;
    _slots = widget.services.api.slots(
        venueId: widget.detail.venue.id, serviceId: _type.id, date: _date);
  }

  Future<void> _submit() async {
    setState(() => _touched = true);
    final slot = _slot;
    final price = _price;
    if (slot == null || price == null || !_addressOk) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final nav = Navigator.of(context);
    final s = bkL10n(context);
    try {
      final record = await widget.services.api.book(
        venueId: widget.detail.venue.id,
        serviceId: _type.id,
        masterId: slot.masterId,
        startsAtIso: slot.startsAtIso,
        comment: _comment.text,
        addressText: _address.text,
        areaSqm: _type.areaBased ? _areaValue : null,
        idempotencyKey: _key,
      );
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
        _error = s.bkError(error.failure);
        if (error.failure == BookingFailure.slotTaken) _loadSlots();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = bkL10n(context);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final price = _price;
    final min = _type.minAreaSqm;
    final max = _type.maxAreaSqm;
    return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Row(children: [
            Expanded(
                child: Text(widget.detail.venue.name,
                    style: theme.textTheme.titleMedium)),
            if (widget.detail.venue.synthetic) const DemoBadge(),
          ]),
          const SizedBox(height: 16),
          Text(s.bkCleaningType, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          RadioGroup<String>(
            groupValue: _type.id,
            onChanged: (id) {
              if (_busy || id == null) return;
              setState(() {
                _type = widget.types.firstWhere((t) => t.id == id);
                _loadSlots();
              });
            },
            child: Column(children: [
              for (final t in widget.types)
                _TypeTile(
                    service: t, selected: t.id == _type.id, enabled: !_busy),
            ]),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _address,
            enabled: !_busy,
            maxLength: 300,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
                labelText: s.bkAddress,
                hintText: s.bkAddressHint,
                prefixIcon: const Icon(Icons.location_on_outlined),
                errorText: _touched && !_addressOk ? s.bkAddressError : null,
                border: const OutlineInputBorder()),
          ),
          if (_type.areaBased) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _area,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 4,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                  labelText: s.bkArea,
                  helperText: '$min–$max м²',
                  prefixIcon: const Icon(Icons.square_foot_outlined),
                  counterText: '',
                  errorText:
                      (_touched || _area.text.isNotEmpty) && price == null
                          ? s.bkAreaError(min!, max!)
                          : null,
                  border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            _EstimateCard(service: _type, price: price),
          ] else ...[
            const SizedBox(height: 12),
            _EstimateCard(service: _type, price: price),
          ],
          const SizedBox(height: 20),
          Text(s.bkDate, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _days,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final day = _today.add(Duration(days: i));
                final label = formatDay(day).split(',');
                return ChoiceChip(
                  selected: day == _date,
                  label: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(label.first.toUpperCase(),
                            style: const TextStyle(fontSize: 11)),
                        Text('${day.day}',
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700)),
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
          Text('${s.bkTime} · ${formatDay(_date)}',
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
                          ? s.bkError(error.failure)
                          : s.bkSlotsError),
                      TextButton(
                          onPressed: () => setState(_loadSlots),
                          child: Text(s.bkRetry)),
                    ]);
              }
              final slots = state.data!;
              if (slots.isEmpty) {
                return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(s.bkNoSlots));
              }
              return Wrap(spacing: 8, runSpacing: 8, children: [
                for (final slot in slots)
                  ChoiceChip(
                    label: Text(formatClock(slot.start)),
                    selected: _slot?.startsAtIso == slot.startsAtIso,
                    onSelected:
                        _busy ? null : (_) => setState(() => _slot = slot),
                  ),
              ]);
            },
          ),
          if (_slot != null) ...[
            const SizedBox(height: 12),
            Text('${s.bkCrew}: ${_slot!.masterName} ${s.bkCrewSynthetic}',
                style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
            const SizedBox(height: 12),
            TextField(
              controller: _comment,
              enabled: !_busy,
              maxLength: 300,
              decoration: InputDecoration(
                  labelText: s.bkCommentLabel,
                  border: const OutlineInputBorder()),
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
                    ? s.bkPickTime
                    : price == null
                        ? s.bkSubmitRequest
                        : s.bkSubmitRequestPrice(formatTenge(price))),
          ),
          const SizedBox(height: 8),
          Text(s.bkCleaningDevNote,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: muted)),
        ]);
  }
}

class _TypeTile extends StatelessWidget {
  const _TypeTile(
      {required this.service, required this.selected, required this.enabled});

  final BookableService service;
  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final s = bkL10n(context);
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: selected ? toneColors('green').background : Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
                color: selected ? primary : theme.colorScheme.outlineVariant,
                width: selected ? 2 : 1)),
        child: RadioListTile<String>(
          value: service.id,
          enabled: enabled,
          title: Text(s.bkCatalogName(service.name),
              style: theme.textTheme.titleMedium),
          subtitle: Text(
              '${service.description}\n${formatDuration(service.durationMinutes)}'
              '${service.areaBased ? ' · ${s.bkEstimateFormula(formatTenge(service.priceMinor), formatTenge(service.pricePerSqmMinor))}' : ' · ${formatTenge(service.priceMinor)}'}'),
          isThreeLine: true,
        ),
      ),
    );
  }
}

class _EstimateCard extends StatelessWidget {
  const _EstimateCard({required this.service, required this.price});

  final BookableService service;
  final int? price;

  @override
  Widget build(BuildContext context) {
    final s = bkL10n(context);
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: toneColors('green').background,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.bkEstimate, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(price == null ? '—' : formatTenge(price!),
              key: const ValueKey('cleaning-estimate'),
              style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(s.bkEstimateNote, style: theme.textTheme.bodySmall),
        ]),
      ),
    );
  }
}
