import 'package:flutter/material.dart';

import '../auto_services.dart';
import '../data/auto_api.dart';
import '../data/auto_models.dart';
import 'auto_booking_flow_screen.dart';
import 'auto_strings.dart';
import 'auto_widgets.dart';

/// One booking: status timeline, cancel, reschedule, customer price decision and repeat booking.
class AutoBookingDetailScreen extends StatefulWidget {
  const AutoBookingDetailScreen(
      {required this.services,
      required this.bookingId,
      this.initial,
      super.key});

  final AutoServices services;
  final String bookingId;
  final AutoBookingRecord? initial;

  @override
  State<AutoBookingDetailScreen> createState() =>
      _AutoBookingDetailScreenState();
}

class _AutoBookingDetailScreenState extends State<AutoBookingDetailScreen> {
  AutoBookingRecord? _record;
  AutoFailure? _loadError;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _record = widget.initial;
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final r = await widget.services.api.booking(widget.bookingId);
      if (mounted) {
        setState(() {
          _record = r;
          _loadError = null;
        });
      }
    } on AutoException catch (e) {
      if (mounted && _record == null) {
        setState(() {
          _loadError = e.failure;
        });
      }
    }
  }

  Future<void> _run(Future<AutoBookingRecord> Function() action) async {
    final s = auL10n(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await action();
      if (mounted) {
        setState(() {
          _record = r;
        });
      }
    } on AutoException catch (e) {
      if (mounted) {
        setState(() {
          _error = s.auError(e.failure);
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

  Future<void> _cancel() async {
    final s = auL10n(context);
    final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
              content: Text(s.auCancelQuestion),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: Text(s.auKeep)),
                FilledButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: Text(s.auCancelBooking)),
              ],
            ));
    if (ok == true) {
      await _run(() => widget.services.api.cancel(widget.bookingId));
    }
  }

  /// The flow only needs ids, names and the duration; prices come from a fresh server quote.
  void _openFlow(AutoBookingRecord b, {required bool move}) {
    final venue = AutoVenue(
        id: b.venueId,
        name: b.venueName,
        description: '',
        addressText: b.venueAddress,
        open: true,
        synthetic: true,
        categories: const []);
    final service = AutoService(
        id: b.serviceId,
        name: b.serviceName,
        description: '',
        category: '',
        durationMinutes: b.durationMinutes,
        priceMinor: b.priceMinor,
        priceKind: b.priceKind,
        conditions: '',
        available: true);
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => AutoBookingFlowScreen(
            services: widget.services,
            venue: venue,
            service: service,
            reschedule: move ? b : null)));
  }

  @override
  Widget build(BuildContext context) {
    final s = auL10n(context);
    final theme = Theme.of(context);
    final b = _record;
    return Scaffold(
      appBar: AppBar(title: Text(s.auDetails)),
      body: b == null
          ? (_loadError != null
              ? AutoStateView.error(error: _loadError!, onRetry: _refresh)
              : const AutoStateView.loading())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(padding: const EdgeInsets.all(16), children: [
                  Text(b.serviceName, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  Semantics(
                      liveRegion: true,
                      child: Text(s.auStatus(b.status),
                          style: theme.textTheme.titleMedium)),
                  const SizedBox(height: 12),
                  Text(b.venueName, style: theme.textTheme.titleMedium),
                  Text(b.venueAddress),
                  const SizedBox(height: 8),
                  Text(
                      '${formatDay(b.startsAt)}, ${formatClock(b.startsAt)} · ${formatDuration(b.durationMinutes)}'),
                  Text(b.vehicle),
                  const SizedBox(height: 8),
                  Text(
                      b.priceKind == 'FIXED'
                          ? formatTenge(b.priceMinor)
                          : s.auFrom(formatTenge(b.priceMinor)),
                      style: theme.textTheme.titleLarge),
                  Text(s.auPriceKind(b.priceKind),
                      style: theme.textTheme.bodySmall),
                  if (b.finalPriceMinor != null &&
                      b.priceApproval == 'APPROVED')
                    Text(
                        '${s.auFinalPrice}: ${formatTenge(b.finalPriceMinor!)}',
                        style: theme.textTheme.titleMedium),
                  if (b.awaitsPriceDecision && b.finalPriceMinor != null) ...[
                    const SizedBox(height: 12),
                    Card(
                      color: theme.colorScheme.secondaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(children: [
                          Text(s.auProposedPrice(
                              formatTenge(b.finalPriceMinor!))),
                          const SizedBox(height: 8),
                          Row(children: [
                            Expanded(
                                child: OutlinedButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _run(() => widget.services.api
                                            .decidePrice(b.id, approve: false)),
                                    child: Text(s.auDecline))),
                            const SizedBox(width: 8),
                            Expanded(
                                child: FilledButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _run(() => widget.services.api
                                            .decidePrice(b.id, approve: true)),
                                    child: Text(s.auApprove))),
                          ]),
                        ]),
                      ),
                    ),
                  ],
                  if (b.cancelReason == 'LATE_CANCEL') Text(s.auLateCancel),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    AutoErrorBanner(_error!),
                  ],
                  const SizedBox(height: 16),
                  if (b.reschedulable)
                    OutlinedButton(
                        onPressed:
                            _busy ? null : () => _openFlow(b, move: true),
                        child: Text(s.auReschedule)),
                  if (b.cancellable) ...[
                    const SizedBox(height: 8),
                    OutlinedButton(
                        onPressed: _busy ? null : _cancel,
                        child: Text(s.auCancelBooking)),
                  ],
                  if (!b.active && b.serviceId.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    FilledButton(
                        onPressed: () => _openFlow(b, move: false),
                        child: Text(s.auRebook)),
                  ],
                  const SizedBox(height: 16),
                  for (final t in b.timeline)
                    ListTile(
                        dense: true,
                        leading: const Icon(Icons.circle, size: 10),
                        title: Text(s.auStatus(t.status))),
                ]),
              ),
            ),
    );
  }
}
