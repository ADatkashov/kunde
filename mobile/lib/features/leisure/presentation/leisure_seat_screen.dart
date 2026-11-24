import 'package:flutter/material.dart';

import '../data/leisure_api.dart';
import 'package:kunde_models/leisure_models.dart';
import '../leisure_services.dart';
import 'leisure_strings.dart';
import 'leisure_summary_screen.dart';
import 'leisure_widgets.dart';

/// Seat selection: legend (free / selected / taken), a screen arc and the plan of the session. States come from the server; a seat taken
/// by someone else meanwhile is refused by the hold request, the plan reloads and the customer picks again.
class LeisureSeatScreen extends StatefulWidget {
  const LeisureSeatScreen(
      {required this.services,
      required this.event,
      required this.session,
      super.key});

  final LeisureServices services;
  final EventDetail event;
  final SessionInfo session;

  @override
  State<LeisureSeatScreen> createState() => _LeisureSeatScreenState();
}

class _LeisureSeatScreenState extends State<LeisureSeatScreen> {
  static const _maxSeats = 8;
  late Future<List<SeatInfo>> _seats =
      widget.services.api.seats(widget.session.id);
  final Set<String> _selected = {};
  bool _busy = false;
  String? _error;
  bool _limitHit = false;

  void _reload() => setState(() {
        _seats = widget.services.api.seats(widget.session.id);
      });

  TicketType? _typeFor(SeatInfo seat) {
    final types = widget.event.ticketTypes;
    for (final t in types) {
      if (t.zone == seat.zone) return t;
    }
    for (final t in types) {
      if (t.zone == null) return t;
    }
    return null;
  }

  Future<void> _continue(List<SeatInfo> seats) async {
    if (_selected.isEmpty || _busy) return;
    final byId = {for (final s in seats) s.id: s};
    final choices = <SeatChoice>[];
    for (final id in _selected) {
      final seat = byId[id];
      final type = seat == null ? null : _typeFor(seat);
      if (type == null) return;
      choices.add(SeatChoice(id, type.id));
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final hold =
          await widget.services.api.holdSeats(widget.session.id, choices);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => LeisureSummaryScreen(
              services: widget.services,
              event: widget.event,
              session: widget.session,
              hold: hold)));
      if (mounted) {
        _selected.clear();
        _reload();
      }
    } on LeisureException catch (ex) {
      if (!mounted) return;
      setState(() => _error = lzL10n(context).lzError(ex.failure));
      if (ex.failure == LeisureFailure.seatTaken ||
          ex.failure == LeisureFailure.notEnoughPlaces) {
        _selected.clear();
        _reload();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = lzL10n(context);
    final theme = Theme.of(context);
    final e = widget.event;
    return Scaffold(
      appBar: AppBar(title: Text(s.lzSeatsTitle), centerTitle: true),
      body: FutureBuilder<List<SeatInfo>>(
        future: _seats,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const LeisureStateView.loading();
          }
          if (snap.hasError) {
            final f = snap.error is LeisureException
                ? (snap.error as LeisureException).failure
                : LeisureFailure.other;
            return LeisureStateView.error(failure: f, onRetry: _reload);
          }
          final seats = snap.data!;
          final byId = {for (final x in seats) x.id: x};
          final rows = <String, List<SeatInfo>>{};
          for (final x in seats) {
            rows.putIfAbsent(x.row, () => []).add(x);
          }
          for (final r in rows.values) {
            r.sort((a, b) => a.number.compareTo(b.number));
          }
          final labels = rows.keys.toList()..sort();
          final columns =
              rows.values.fold<int>(0, (m, r) => r.length > m ? r.length : m);
          var total = 0;
          for (final id in _selected) {
            total += byId[id]?.priceMinor ?? 0;
          }
          final selectedLabels = (_selected
                  .map((id) => byId[id]?.label)
                  .whereType<String>()
                  .toList()
                ..sort())
              .join(', ');
          return Column(children: [
            Expanded(
              child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(
                                width: 56,
                                height: 72,
                                child: EventPhoto(
                                    url: e.photos.isEmpty
                                        ? null
                                        : e.photos.first,
                                    category: e.category.code,
                                    iconSize: 26)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(e.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                              fontWeight: FontWeight.w800)),
                                  Text(s.lzWhen(widget.session.startsAt),
                                      style: theme.textTheme.bodySmall),
                                  Text(e.venue.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall),
                                ]),
                          ),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                        alignment: WrapAlignment.spaceEvenly,
                        spacing: 16,
                        runSpacing: 6,
                        children: [
                          _Legend(
                              color: theme.colorScheme.primaryContainer,
                              label: s.lzSeatFree),
                          _Legend(
                              color: theme.colorScheme.primary,
                              label: s.lzSeatSelected),
                          _Legend(
                              color: theme.colorScheme.outlineVariant,
                              label: s.lzSeatTaken),
                        ]),
                    const SizedBox(height: 14),
                    Semantics(
                      label: s.lzScreen,
                      child: Column(children: [
                        CustomPaint(
                            size: const Size(double.infinity, 28),
                            painter: _ScreenArc(theme.colorScheme.primary)),
                        Text(s.lzScreen, style: theme.textTheme.labelSmall),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(builder: (context, box) {
                      const labelW = 26.0;
                      final size = ((box.maxWidth - labelW * 2) / columns)
                          .clamp(30.0, 44.0);
                      final grid = Column(children: [
                        for (final label in labels)
                          Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                    width: labelW,
                                    child: Center(
                                        child: Text(label,
                                            style:
                                                theme.textTheme.labelMedium))),
                                for (final seat in rows[label]!)
                                  _SeatButton(
                                    seat: seat,
                                    size: size,
                                    selected: _selected.contains(seat.id),
                                    semantics: s.lzSeatSemantics(
                                        seat.label,
                                        s.lzZone(seat.zone),
                                        _selected.contains(seat.id)
                                            ? s.lzSeatSelected
                                            : seat.state == SeatState.free
                                                ? s.lzSeatFree
                                                : s.lzSeatTaken,
                                        seat.priceMinor == null
                                            ? ''
                                            : formatTenge(seat.priceMinor!)),
                                    onTap: () => setState(() {
                                      _limitHit = false;
                                      if (_selected.contains(seat.id)) {
                                        _selected.remove(seat.id);
                                      } else if (_selected.length >=
                                          _maxSeats) {
                                        _limitHit = true;
                                      } else {
                                        _selected.add(seat.id);
                                      }
                                    }),
                                  ),
                                SizedBox(
                                    width: labelW,
                                    child: Center(
                                        child: Text(label,
                                            style:
                                                theme.textTheme.labelMedium))),
                              ]),
                      ]);
                      final needed = columns * 30.0 + labelW * 2;
                      return needed > box.maxWidth
                          ? SingleChildScrollView(
                              scrollDirection: Axis.horizontal, child: grid)
                          : grid;
                    }),
                    if (_limitHit)
                      Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: LeisureErrorBanner(s.lzMaxSeats)),
                    if (_error != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: LeisureErrorBanner(_error!)),
                  ]),
            ),
            PrimaryBar(
              label: s.lzContinue,
              busy: _busy,
              onPressed: _selected.isEmpty ? null : () => _continue(seats),
              top: Row(children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                            liveRegion: true,
                            child: Text(
                                _selected.isEmpty
                                    ? s.lzNoneSelected
                                    : '${s.lzSelectedSeats(_selected.length)} · $selectedLabels',
                                style: theme.textTheme.bodySmall)),
                        Text(formatTenge(total),
                            style: theme.textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900)),
                      ]),
                ),
              ]),
            ),
          ]);
        },
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(6))),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ]);
}

class _SeatButton extends StatelessWidget {
  const _SeatButton(
      {required this.seat,
      required this.size,
      required this.selected,
      required this.onTap,
      required this.semantics});

  final SeatInfo seat;
  final double size;
  final bool selected;
  final VoidCallback onTap;
  final String semantics;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final free = seat.state == SeatState.free;
    final vip = seat.zone == 'VIP';
    final Color fill = selected
        ? scheme.primary
        : free
            ? (vip
                ? const Color(0xFFF2C77D).withValues(alpha: .75)
                : scheme.primaryContainer)
            : scheme.outlineVariant.withValues(alpha: .7);
    return Semantics(
      button: true,
      enabled: free || selected,
      selected: selected,
      label: semantics,
      child: GestureDetector(
        onTap: free || selected ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: size - 4,
            height: size - 4,
            decoration: BoxDecoration(
                color: fill, borderRadius: BorderRadius.circular(8)),
            child: selected
                ? Icon(Icons.check_rounded, size: 18, color: scheme.onPrimary)
                : null,
          ),
        ),
      ),
    );
  }
}

class _ScreenArc extends CustomPainter {
  const _ScreenArc(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * .08, size.height)
      ..quadraticBezierTo(
          size.width / 2, -size.height * .5, size.width * .92, size.height);
    canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: .55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant _ScreenArc old) => old.color != color;
}
