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
  String? _notice;
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

  Future<void> _review() async {
    final s = auL10n(context);
    final result = await showDialog<(int, String)>(
        context: context, builder: (_) => const _ReviewDialog());
    if (result == null) return;
    await _feedback(
        () => widget.services.api
            .review(widget.bookingId, rating: result.$1, text: result.$2),
        s.auReviewThanks);
  }

  Future<void> _complain() async {
    final s = auL10n(context);
    final result = await showDialog<(String, String)>(
        context: context, builder: (_) => const _ComplaintDialog());
    if (result == null) return;
    await _feedback(
        () => widget.services.api.complain(widget.bookingId,
            kind: result.$1, description: result.$2),
        s.auComplaintSent);
  }

  Future<void> _feedback(Future<void> Function() action, String done) async {
    final s = auL10n(context);
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
      if (mounted) setState(() => _notice = done);
    } on AutoException catch (e) {
      if (mounted) setState(() => _error = s.auError(e.failure));
    } finally {
      if (mounted) setState(() => _busy = false);
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
                  if (_notice != null)
                    Semantics(
                        liveRegion: true,
                        child:
                            Text(_notice!, style: theme.textTheme.titleSmall)),
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
                  if (b.status == 'COMPLETED')
                    OutlinedButton(
                        onPressed: _busy ? null : _review,
                        child: Text(s.auReview)),
                  if (!b.active && b.status != 'CANCELLED') ...[
                    const SizedBox(height: 8),
                    OutlinedButton(
                        onPressed: _busy ? null : _complain,
                        child: Text(s.auComplain)),
                  ],
                  if (!b.active && b.serviceId.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    FilledButton(
                        onPressed: () => _openFlow(b, move: false),
                        child: Text(s.auRebook)),
                  ],
                  if (b.payment != null) ...[
                    const SizedBox(height: 12),
                    ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.payments_outlined),
                        title: Text(s.auPaymentStatus(b.payment!.isTest
                            ? b.payment!.status
                            : 'PAY_ON_SITE')),
                        subtitle:
                            b.payment!.isTest ? Text(s.auPayTestNote) : null),
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

/// Owns its controller so it is disposed only after the dialog route has closed.
class _ReviewDialog extends StatefulWidget {
  const _ReviewDialog();
  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  final _text = TextEditingController();
  int _rating = 0;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = auL10n(context);
    return AlertDialog(
      title: Text(s.auReviewTitle),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Wrap(children: [
          for (var i = 1; i <= 5; i++)
            IconButton(
              tooltip: '$i',
              icon: Icon(i <= _rating
                  ? Icons.star_rounded
                  : Icons.star_outline_rounded),
              onPressed: () => setState(() => _rating = i),
            ),
        ]),
        TextField(
            controller: _text,
            maxLength: 500,
            decoration: InputDecoration(labelText: s.auReviewText)),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.auCancelAction)),
        FilledButton(
            onPressed: _rating == 0
                ? null
                : () => Navigator.pop(context, (_rating, _text.text)),
            child: Text(s.auSend)),
      ],
    );
  }
}

class _ComplaintDialog extends StatefulWidget {
  const _ComplaintDialog();
  @override
  State<_ComplaintDialog> createState() => _ComplaintDialogState();
}

class _ComplaintDialogState extends State<_ComplaintDialog> {
  final _text = TextEditingController();
  String _kind = 'QUALITY';

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = auL10n(context);
    return AlertDialog(
      title: Text(s.auComplaintTitle),
      content: SingleChildScrollView(
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(spacing: 8, children: [
                for (final k in const [
                  'QUALITY',
                  'PRICE',
                  'BEHAVIOR',
                  'NO_SHOW',
                  'OTHER'
                ])
                  ChoiceChip(
                      label: Text(s.auComplaintKind(k)),
                      selected: _kind == k,
                      onSelected: (_) => setState(() => _kind = k)),
              ]),
              TextField(
                controller: _text,
                maxLength: 500,
                minLines: 2,
                maxLines: 4,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: s.auComplaintText),
              ),
            ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.auCancelAction)),
        FilledButton(
            onPressed: _text.text.trim().length < 5
                ? null
                : () => Navigator.pop(context, (_kind, _text.text)),
            child: Text(s.auSend)),
      ],
    );
  }
}
