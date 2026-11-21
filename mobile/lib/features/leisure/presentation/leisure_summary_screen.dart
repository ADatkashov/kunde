import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kunde_design/kunde_design.dart';

import '../data/leisure_models.dart';
import '../leisure_services.dart';
import 'leisure_payment_screen.dart';
import 'leisure_strings.dart';
import 'leisure_widgets.dart';

/// Booking summary: the order as priced by the server, the hold countdown, the age confirmation and the total before any payment.
/// Leaving the screen without paying releases the hold so the places are free again immediately.
class LeisureSummaryScreen extends StatefulWidget {
  const LeisureSummaryScreen(
      {required this.services,
      required this.event,
      required this.session,
      required this.hold,
      super.key});

  final LeisureServices services;
  final EventDetail event;
  final SessionInfo session;
  final Hold hold;

  @override
  State<LeisureSummaryScreen> createState() => _LeisureSummaryScreenState();
}

class _LeisureSummaryScreenState extends State<LeisureSummaryScreen> {
  Timer? _timer;
  late Duration _left = _remaining();
  bool _age = false;

  Duration _remaining() {
    final d = widget.hold.expiresAt.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _left = _remaining());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    // a consumed hold is untouched by the release, so this is safe after a successful payment too
    unawaited(widget.services.api.release(widget.hold.id).catchError((_) {}));
    super.dispose();
  }

  String _mmss(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final s = lzL10n(context);
    final theme = Theme.of(context);
    final e = widget.event;
    final h = widget.hold;
    final expired = _left == Duration.zero;
    final needsAge = e.minAge > 0;
    final grouped = <String, List<HoldLine>>{};
    for (final l in h.lines) {
      grouped.putIfAbsent('${l.ticketType}|${l.priceMinor}', () => []).add(l);
    }
    final seats = h.lines.map((l) => l.seat).whereType<String>().toList()
      ..sort();
    return Scaffold(
      appBar: AppBar(title: Text(s.lzBooking), centerTitle: true),
      bottomNavigationBar: PrimaryBar(
        label: s.lzContinue,
        onPressed: expired || (needsAge && !_age)
            ? null
            : () => Navigator.of(context).push<void>(MaterialPageRoute<void>(
                builder: (_) => LeisurePaymentScreen(
                    services: widget.services,
                    event: e,
                    session: widget.session,
                    hold: h,
                    ageConfirmed: _age || !needsAge))),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        BookingStepper(current: 2, labels: [
          s.lzStepSession,
          e.bookingType == BookingType.seatMap ? s.lzStepSeats : s.lzTickets,
          s.lzStepPurchase
        ]),
        const SizedBox(height: 18),
        Text(s.lzYourOrder,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                    width: 72,
                    height: 92,
                    child: EventPhoto(
                        url: e.photos.isEmpty ? null : e.photos.first,
                        category: e.category.code,
                        iconSize: 30)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.title,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      _Line(Icons.place_outlined, e.venue.name),
                      _Line(Icons.event_rounded,
                          s.lzWhen(widget.session.startsAt)),
                      if (seats.isNotEmpty)
                        _Line(Icons.event_seat_rounded,
                            '${s.lzSeats}: ${seats.join(', ')}')
                      else
                        _Line(Icons.person_outline_rounded,
                            '${s.lzGuestsCount}: ${h.guests}'),
                    ]),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        Text(s.lzCost,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        for (final g in grouped.values)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(
                  child: Text(
                      '${g.length} × ${g.first.ticketType} · ${formatTenge(g.first.priceMinor)}')),
              Text(formatTenge(g.first.priceMinor * g.length)),
            ]),
          ),
        const Divider(height: 24),
        Row(children: [
          Expanded(
              child: Text(s.lzTotal,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900))),
          Text(formatTenge(h.totalMinor),
              style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: theme.colorScheme.primary)),
        ]),
        const SizedBox(height: 16),
        Semantics(
          liveRegion: expired,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: expired
                    ? theme.colorScheme.errorContainer
                    : theme.colorScheme.primaryContainer.withValues(alpha: .6),
                borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Icon(expired ? Icons.timer_off_rounded : Icons.timer_outlined),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(expired
                      ? s.lzHoldExpired
                      : '${s.lzHoldLeft} ${_mmss(_left)}')),
            ]),
          ),
        ),
        if (needsAge)
          CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _age,
              onChanged: (v) => setState(() => _age = v ?? false),
              title: Text(s.lzAgeConfirm(e.minAge))),
        if (e.manualConfirmation)
          Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(s.lzManualConfirm, style: theme.textTheme.bodySmall)),
        const SizedBox(height: 10),
        Row(children: [
          const Icon(Icons.verified_user_outlined,
              size: 18, color: KundePalette.violet),
          const SizedBox(width: 8),
          Expanded(child: Text(s.lzSafeNote, style: theme.textTheme.bodySmall)),
        ]),
      ]),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon,
              size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
              child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
        ]),
      );
}
