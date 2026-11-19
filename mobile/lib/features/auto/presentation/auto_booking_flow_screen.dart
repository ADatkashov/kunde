import 'package:flutter/material.dart';

import '../../../core/localization/kunde_localizations.dart';
import '../auto_services.dart';
import '../data/auto_api.dart';
import '../data/auto_models.dart';
import 'auto_booking_detail_screen.dart';
import 'auto_strings.dart';
import 'auto_widgets.dart';
import 'vehicles_screen.dart';

/// Booking flow: car → date → free slot (server list) → server quote → confirmation.
/// With [reschedule] set the same date/slot picker moves an existing booking instead.
class AutoBookingFlowScreen extends StatefulWidget {
  const AutoBookingFlowScreen(
      {required this.services,
      required this.venue,
      required this.service,
      this.reschedule,
      super.key});

  final AutoServices services;
  final AutoVenue venue;
  final AutoService service;
  final AutoBookingRecord? reschedule;

  @override
  State<AutoBookingFlowScreen> createState() => _AutoBookingFlowScreenState();
}

class _AutoBookingFlowScreenState extends State<AutoBookingFlowScreen> {
  static const _days = 14;
  final DateTime _today = almatyToday();
  late DateTime _date = _today;
  Future<List<AutoSlot>>? _slots;
  Future<List<Vehicle>>? _vehicles;
  Vehicle? _vehicle;
  AutoSlot? _slot;
  AutoQuote? _quote;
  bool _busy = false;
  String? _error;
  String _key = AutoApi.newIdempotencyKey();

  bool get _moving => widget.reschedule != null;

  @override
  void initState() {
    super.initState();
    if (!_moving) _vehicles = widget.services.api.vehicles();
    _loadSlots();
  }

  void _loadSlots() {
    _slot = null;
    _quote = null;
    _slots = widget.services.api.slots(
        venueId: widget.venue.id, serviceId: widget.service.id, date: _date);
  }

  Future<void> _pickSlot(AutoSlot slot) async {
    setState(() {
      _slot = slot;
      _quote = null;
      _error = null;
    });
    if (_moving || _vehicle == null) return;
    await _requestQuote();
  }

  Future<void> _requestQuote() async {
    final s = auL10n(context);
    final slot = _slot;
    final vehicle = _vehicle;
    if (slot == null || vehicle == null) return;
    setState(() {
      _busy = true;
    });
    try {
      final q = await widget.services.api.quote(
          venueId: widget.venue.id,
          serviceId: widget.service.id,
          vehicleId: vehicle.id,
          startsAtIso: slot.startsAtIso);
      if (mounted && _slot == slot) {
        setState(() {
          _quote = q;
        });
      }
    } on AutoException catch (e) {
      if (mounted) {
        setState(() {
          _error = s.auError(e.failure);
          if (e.failure == AutoFailure.slotTaken) _loadSlots();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _confirm() async {
    final s = auL10n(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final AutoBookingRecord record;
      if (_moving) {
        record = await widget.services.api
            .reschedule(widget.reschedule!.id, _slot!.startsAtIso);
      } else {
        record = await widget.services.api
            .book(quoteId: _quote!.id, idempotencyKey: _key);
      }
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
          builder: (_) => AutoBookingDetailScreen(
              services: widget.services,
              bookingId: record.id,
              initial: record)));
    } on AutoException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = s.auError(e.failure);
        if (e.failure == AutoFailure.slotTaken) _loadSlots();
        if (e.failure == AutoFailure.quoteExpired) {
          _quote = null;
          _key = AutoApi.newIdempotencyKey();
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = auL10n(context);
    final theme = Theme.of(context);
    final canConfirm = !_busy &&
        _slot != null &&
        (_moving || (_vehicle != null && _quote != null));
    return Scaffold(
      appBar: AppBar(title: Text(widget.service.name)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Text(widget.venue.name, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            if (!_moving) _vehiclePicker(s),
            Text(s.auChooseDate, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            SizedBox(
              height: 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _days,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final d = _today.add(Duration(days: i));
                  return ChoiceChip(
                    label: Text(formatDay(d)),
                    selected: d == _date,
                    onSelected: (_) => setState(() {
                      _date = d;
                      _loadSlots();
                    }),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Text(s.auChooseTime, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            FutureBuilder<List<AutoSlot>>(
              future: _slots,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const SizedBox(
                      height: 80, child: AutoStateView.loading());
                }
                if (snap.hasError) {
                  final f = snap.error is AutoException
                      ? (snap.error as AutoException).failure
                      : AutoFailure.other;
                  return SizedBox(
                      height: 160,
                      child: AutoStateView.error(
                          error: f, onRetry: () => setState(_loadSlots)));
                }
                final slots = snap.data!;
                if (slots.isEmpty) return Text(s.auNoSlots);
                return Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final sl in slots)
                    ChoiceChip(
                        label: Text(formatClock(sl.time)),
                        selected: _slot?.startsAtIso == sl.startsAtIso,
                        onSelected: _busy ? null : (_) => _pickSlot(sl)),
                ]);
              },
            ),
            if (_quote != null) ...[
              const SizedBox(height: 16),
              _quoteCard(s, theme, _quote!),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              AutoErrorBanner(_error!),
            ],
            const SizedBox(height: 16),
            FilledButton(
                onPressed: canConfirm ? _confirm : null,
                child: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_moving ? s.auReschedule : s.auConfirmBooking)),
            const SizedBox(height: 8),
            Text(s.auDemoNote, style: theme.textTheme.bodySmall),
          ]),
        ),
      ),
    );
  }

  Widget _vehiclePicker(KundeLocalizations s) {
    final theme = Theme.of(context);
    return FutureBuilder<List<Vehicle>>(
      future: _vehicles,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox(height: 56, child: AutoStateView.loading());
        }
        if (snap.hasError) {
          return AutoStateView.error(
              error: snap.error is AutoException
                  ? (snap.error as AutoException).failure
                  : AutoFailure.other,
              onRetry: () => setState(() {
                    _vehicles = widget.services.api.vehicles();
                  }));
        }
        final list = snap.data!;
        if (list.isEmpty) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: OutlinedButton.icon(
                onPressed: () async {
                  final saved = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                          builder: (_) =>
                              VehicleFormScreen(services: widget.services)));
                  if (saved == true && mounted) {
                    setState(() {
                      _vehicles = widget.services.api.vehicles();
                    });
                  }
                },
                icon: const Icon(Icons.add_rounded),
                label: Text(s.auAddVehicle)),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.auChooseVehicle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final v in list)
                ChoiceChip(
                    label: Text(v.label),
                    selected: _vehicle?.id == v.id,
                    onSelected: (_) {
                      setState(() {
                        _vehicle = v;
                      });
                      if (_slot != null) _requestQuote();
                    }),
            ]),
          ]),
        );
      },
    );
  }

  Widget _quoteCard(KundeLocalizations s, ThemeData theme, AutoQuote q) => Card(
        elevation: 0,
        color: theme.colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.auQuoteTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
                q.priceKind == 'FIXED'
                    ? formatTenge(q.priceMinor)
                    : s.auFrom(formatTenge(q.priceMinor)),
                style: theme.textTheme.headlineSmall),
            Text(s.auPriceKind(q.priceKind)),
            Text(s.auDuration(formatDuration(q.durationMinutes))),
            Text(s.auQuoteValid(formatClock(
                q.expiresAt.toUtc().add(const Duration(hours: 5))))),
            const SizedBox(height: 4),
            Text(q.cancellationTerms, style: theme.textTheme.bodySmall),
          ]),
        ),
      );
}
