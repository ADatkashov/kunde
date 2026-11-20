import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kunde_design/kunde_design.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../data/leisure_api.dart';
import '../data/leisure_models.dart';
import '../leisure_services.dart';
import 'leisure_event_screen.dart';
import 'leisure_strings.dart';
import 'leisure_widgets.dart';

/// Electronic ticket: the QR carries only `KT1.<id>.<secret>` (no personal data) and is verified by the server at the gate. The screen refreshes
/// itself, so a ticket scanned at the entrance turns "Used" without reopening. Cancellation, review and complaint use the same order endpoints.
class LeisureTicketScreen extends StatefulWidget {
  const LeisureTicketScreen(
      {required this.services,
      required this.orderId,
      this.initial,
      this.justBooked = false,
      super.key});

  final LeisureServices services;
  final String orderId;
  final LeisureOrder? initial;
  final bool justBooked;

  @override
  State<LeisureTicketScreen> createState() => _LeisureTicketScreenState();
}

class _LeisureTicketScreenState extends State<LeisureTicketScreen> {
  LeisureOrder? _order;
  LeisureFailure? _failure;
  Timer? _poll;
  bool _busy = false;
  String? _message;
  final _pager = PageController();
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _order = widget.initial;
    unawaited(_load());
    _poll =
        Timer.periodic(const Duration(seconds: 12), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _pager.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final o = await widget.services.api.order(widget.orderId);
      if (mounted) {
        setState(() {
          _order = o;
          _failure = null;
        });
      }
    } on LeisureException catch (e) {
      if (mounted && !silent && _order == null) {
        setState(() => _failure = e.failure);
      }
    }
  }

  Future<void> _cancel() async {
    final s = lzL10n(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.lzCancelBooking),
        content: Text(_order?.testPayment == true
            ? s.lzCancelConfirm
            : s.lzCancelBooking),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.lzKeep)),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(s.lzCancelBooking)),
        ],
      ),
    );
    if (yes != true) return;
    await _act(() async {
      final o = await widget.services.api.cancel(widget.orderId);
      if (mounted) setState(() => _order = o);
    });
  }

  Future<void> _act(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } on LeisureException catch (e) {
      if (mounted) {
        setState(() => _message = lzL10n(context).lzError(e.failure));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _review() async {
    final s = lzL10n(context);
    final result = await showModalBottomSheet<(int, String)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _ReviewSheet(),
    );
    if (result == null) return;
    await _act(() async {
      await widget.services.api.review(widget.orderId, result.$1, result.$2);
      await _load(silent: true);
      if (mounted) setState(() => _message = s.lzReviewThanks);
    });
  }

  Future<void> _complain() async {
    final s = lzL10n(context);
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _ComplaintSheet(),
    );
    if (text == null || text.trim().isEmpty) return;
    await _act(() async {
      await widget.services.api.complain(widget.orderId, text.trim());
      if (mounted) setState(() => _message = s.lzComplainSent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = lzL10n(context);
    final theme = Theme.of(context);
    final o = _order;
    if (o == null) {
      return Scaffold(
        appBar: AppBar(title: Text(s.lzTicketTitle), centerTitle: true),
        body: _failure != null
            ? LeisureStateView.error(failure: _failure!, onRetry: _load)
            : const LeisureStateView.loading(),
      );
    }
    final tickets = o.tickets.where((t) => t.status != 'CANCELLED').toList();
    final shown = tickets.isEmpty ? o.tickets : tickets;
    final cancelledOrUsed = o.cancelled;
    return Scaffold(
      appBar: AppBar(title: Text(s.lzTicketTitle), centerTitle: true),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.justBooked) ...[
                          _Banner(
                              icon: Icons.check_circle_rounded,
                              text: o.pending
                                  ? s.lzStatus('PENDING')
                                  : s.lzStatus('CONFIRMED')),
                          const SizedBox(height: 12),
                        ],
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            gradient: cancelledOrUsed
                                ? LinearGradient(colors: [
                                    Colors.grey.shade600,
                                    Colors.grey.shade500
                                  ])
                                : const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                        Color(0xFF7055F5),
                                        Color(0xFF9B7DFF)
                                      ]),
                            boxShadow: const [
                              BoxShadow(
                                  color: KundePalette.shadow,
                                  blurRadius: 24,
                                  offset: Offset(0, 10))
                            ],
                          ),
                          padding: const EdgeInsets.all(18),
                          child: Column(children: [
                            Text('KUNDE',
                                style: theme.textTheme.titleLarge?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 2)),
                            const SizedBox(height: 14),
                            if (shown.isEmpty)
                              const SizedBox(height: 120)
                            else
                              SizedBox(
                                height: 272,
                                child: PageView.builder(
                                  controller: _pager,
                                  itemCount: shown.length,
                                  onPageChanged: (i) =>
                                      setState(() => _page = i),
                                  itemBuilder: (_, i) => _QrCard(
                                      ticket: shown[i],
                                      dimmed: cancelledOrUsed,
                                      noQr: s.lzNoQrYet,
                                      statusText: s.lzStatus(shown[i].status)),
                                ),
                              ),
                            const SizedBox(height: 8),
                            if (shown.length > 1)
                              Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    for (var i = 0; i < shown.length; i++)
                                      Container(
                                          width: 8,
                                          height: 8,
                                          margin: const EdgeInsets.symmetric(
                                              horizontal: 3),
                                          decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: i == _page
                                                  ? Colors.white
                                                  : Colors.white38)),
                                  ]),
                            const SizedBox(height: 6),
                            Semantics(
                              label:
                                  '${s.lzTicketNo} ${shown.isEmpty ? o.shortId : shown[_page.clamp(0, shown.length - 1)].shortId}',
                              child: Text(
                                  '${s.lzTicketNo} KND-${shown.isEmpty ? o.shortId : shown[_page.clamp(0, shown.length - 1)].shortId}',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: .5)),
                            ),
                            Text(s.lzQrHint,
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: Colors.white70)),
                          ]),
                        ),
                        const SizedBox(height: 16),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          child: SizedBox(
                                              width: 60,
                                              height: 76,
                                              child: EventPhoto(
                                                  url: o.photoUrl,
                                                  category: o.categoryCode,
                                                  iconSize: 26)),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                            child: Text(o.eventTitle,
                                                style: theme
                                                    .textTheme.titleMedium
                                                    ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w800))),
                                      ]),
                                  const SizedBox(height: 12),
                                  _Detail(
                                      Icons.place_outlined,
                                      [o.venueName, o.venueAddress]
                                          .where((x) => x.isNotEmpty)
                                          .join(', ')),
                                  _Detail(Icons.event_rounded,
                                      s.lzWhen(o.startsAt)),
                                  _Detail(Icons.person_outline_rounded,
                                      '${s.lzGuestsCount}: ${o.guests}'),
                                  if (o.seats.isNotEmpty)
                                    _Detail(Icons.event_seat_rounded,
                                        '${s.lzSeats}: ${o.seats}'),
                                  _Detail(Icons.payments_outlined,
                                      '${formatTenge(o.totalMinor)} · ${o.testPayment ? s.lzTestCard : s.lzPayOnSite}'),
                                  _Detail(Icons.flag_outlined,
                                      '${s.lzTicketStatus}: ${s.lzStatus(o.status)}'),
                                  if (o.refundedMinor > 0)
                                    _Detail(Icons.undo_rounded,
                                        '${s.lzRefunded}: ${formatTenge(o.refundedMinor)}'),
                                  if (o.rules.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(s.lzRules,
                                        style: theme.textTheme.titleSmall),
                                    Text(o.rules,
                                        style: theme.textTheme.bodySmall),
                                  ],
                                  const SizedBox(height: 8),
                                  if (o.testPayment ||
                                      o.paymentMethod == 'PAY_ON_SITE')
                                    Text(s.lzTicketTestNote,
                                        style: theme.textTheme.bodySmall),
                                ]),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_message != null) ...[
                          LeisureErrorBanner(_message!),
                          const SizedBox(height: 12)
                        ],
                        Wrap(spacing: 10, runSpacing: 10, children: [
                          OutlinedButton.icon(
                            onPressed: () async {
                              await Clipboard.setData(
                                  ClipboardData(text: 'KND-${o.shortId}'));
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(s.lzCopied)));
                              }
                            },
                            icon: const Icon(Icons.copy_rounded),
                            label: Text(s.lzCopyNo),
                          ),
                          if (o.cancellable)
                            OutlinedButton.icon(
                                onPressed: _busy ? null : _cancel,
                                icon: const Icon(Icons.cancel_outlined),
                                label: Text(s.lzCancelBooking)),
                          if (o.canReview)
                            FilledButton.icon(
                                onPressed: _busy ? null : _review,
                                icon: const Icon(Icons.star_rounded),
                                label: Text(s.lzWriteReview)),
                          if (o.cancelled || o.phase == 'COMPLETED')
                            FilledButton.tonalIcon(
                              onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                      builder: (_) => LeisureEventScreen(
                                          services: widget.services,
                                          eventId: o.eventId))),
                              icon: const Icon(Icons.replay_rounded),
                              label: Text(s.lzRebook),
                            ),
                          TextButton.icon(
                              onPressed: _busy ? null : _complain,
                              icon: const Icon(Icons.flag_outlined),
                              label: Text(s.lzComplain)),
                        ]),
                        if (o.cancellable)
                          Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                  s.lzFreeUntil(s.lzWhen(o.cancelUntil)),
                                  style: theme.textTheme.bodySmall)),
                        if (!o.cancellable &&
                            !o.cancelled &&
                            o.phase == 'UPCOMING')
                          Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(s.lzCancelClosed,
                                  style: theme.textTheme.bodySmall)),
                      ]),
                ),
              ),
            ]),
      ),
    );
  }
}

class _QrCard extends StatelessWidget {
  const _QrCard(
      {required this.ticket,
      required this.dimmed,
      required this.noQr,
      required this.statusText});

  final Ticket ticket;
  final bool dimmed;
  final String noQr;
  final String statusText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final qr = ticket.qr;
    final used = ticket.status == 'USED';
    return Center(
      child: Container(
        width: 224,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 176,
            height: 176,
            child: qr == null
                ? Center(
                    child: Text(noQr,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.black87)))
                : Semantics(
                    label: 'QR ${ticket.shortId}',
                    image: true,
                    child: Opacity(
                      opacity: dimmed || used ? .25 : 1,
                      child: QrImageView(
                          data: qr,
                          size: 176,
                          backgroundColor: Colors.white,
                          errorCorrectionLevel: QrErrorCorrectLevel.M,
                          padding: EdgeInsets.zero),
                    ),
                  ),
          ),
          const SizedBox(height: 6),
          Text('$statusText${ticket.seat != null ? ' · ${ticket.seat}' : ''}',
              style: theme.textTheme.labelLarge?.copyWith(
                  color: Colors.black87, fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => text.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ]),
        );
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: const Color(0xFFE2F6EA),
              borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            Icon(icon, color: const Color(0xFF1B7A44)),
            const SizedBox(width: 10),
            Expanded(
                child: Text(text,
                    style: const TextStyle(
                        color: Color(0xFF14532D),
                        fontWeight: FontWeight.w700))),
          ]),
        ),
      );
}

class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet();

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  int _rating = 5;
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = lzL10n(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.lzWriteReview,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  tooltip: '$i',
                  iconSize: 36,
                  onPressed: () => setState(() => _rating = i),
                  icon: Icon(
                      i <= _rating
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      color: KundePalette.gold),
                ),
            ]),
            TextField(
                controller: _text,
                maxLines: 3,
                maxLength: 1000,
                decoration: InputDecoration(
                    hintText: s.lzReviewHint,
                    border: const OutlineInputBorder())),
            const SizedBox(height: 8),
            SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                    onPressed: () =>
                        Navigator.pop(context, (_rating, _text.text.trim())),
                    child: Text(s.lzSend))),
          ]),
    );
  }
}

class _ComplaintSheet extends StatefulWidget {
  const _ComplaintSheet();

  @override
  State<_ComplaintSheet> createState() => _ComplaintSheetState();
}

class _ComplaintSheetState extends State<_ComplaintSheet> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = lzL10n(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.lzComplain,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            TextField(
                controller: _text,
                maxLines: 4,
                maxLength: 1000,
                decoration: InputDecoration(
                    hintText: s.lzComplainHint,
                    border: const OutlineInputBorder())),
            const SizedBox(height: 8),
            SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                    onPressed: () => Navigator.pop(context, _text.text),
                    child: Text(s.lzSend))),
          ]),
    );
  }
}
