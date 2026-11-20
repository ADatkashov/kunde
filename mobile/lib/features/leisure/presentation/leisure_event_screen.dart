import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kunde_design/kunde_design.dart';

import '../data/leisure_api.dart';
import '../data/leisure_models.dart';
import '../leisure_services.dart';
import 'leisure_seat_screen.dart';
import 'leisure_strings.dart';
import 'leisure_summary_screen.dart';
import 'leisure_widgets.dart';

DateTime _almatyToday() {
  final now = DateTime.now().toUtc().add(const Duration(hours: 5));
  return DateTime(now.year, now.month, now.day);
}

/// Event details: gallery, price, availability, schedule with real free places, about/rules/cancellation, reviews and a sticky booking button.
class LeisureEventScreen extends StatefulWidget {
  const LeisureEventScreen(
      {required this.services, required this.eventId, super.key});

  final LeisureServices services;
  final String eventId;

  @override
  State<LeisureEventScreen> createState() => _LeisureEventScreenState();
}

class _LeisureEventScreenState extends State<LeisureEventScreen> {
  late Future<EventDetail> _detail = widget.services.api.event(widget.eventId);
  Future<List<SessionInfo>>? _sessions;
  Future<List<Review>>? _reviews;
  int _tab = 0;
  DateTime? _day;
  SessionInfo? _session;
  bool _busy = false;
  String? _error;
  bool _favorite = false;
  final _gallery = PageController();
  int _page = 0;

  @override
  void initState() {
    super.initState();
    unawaited(widget.services.api.favorites().then((f) {
      if (mounted) setState(() => _favorite = f.contains(widget.eventId));
    }).catchError((_) {}));
  }

  @override
  void dispose() {
    _gallery.dispose();
    super.dispose();
  }

  void _reload() => setState(() {
        _detail = widget.services.api.event(widget.eventId);
        _sessions = null;
        _reviews = null;
      });

  Future<List<SessionInfo>> _loadSessions() =>
      widget.services.api.sessions(widget.eventId, _almatyToday(), days: 21);

  Future<void> _toggleFavorite() async {
    final on = !_favorite;
    setState(() => _favorite = on);
    try {
      await widget.services.api.setFavorite(widget.eventId, on);
    } on LeisureException {
      if (mounted) setState(() => _favorite = !on);
    }
  }

  Future<void> _continue(EventDetail e) async {
    final session = _session;
    if (session == null || _busy) return;
    setState(() => _error = null);
    if (e.bookingType == BookingType.seatMap) {
      await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => LeisureSeatScreen(
              services: widget.services, event: e, session: session)));
      if (mounted) {
        setState(() {
          _sessions = _loadSessions();
        });
      }
      return;
    }
    final picked = await showModalBottomSheet<_TicketChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _TicketSheet(event: e, session: session),
    );
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final hold = await widget.services.api
          .holdTickets(session.id, picked.quantities, guests: picked.guests);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => LeisureSummaryScreen(
              services: widget.services,
              event: e,
              session: session,
              hold: hold)));
      if (mounted) {
        setState(() {
          _sessions = _loadSessions();
        });
      }
    } on LeisureException catch (ex) {
      if (mounted) setState(() => _error = lzL10n(context).lzError(ex.failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = lzL10n(context);
    return FutureBuilder<EventDetail>(
      future: _detail,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Scaffold(
              appBar: AppBar(), body: const LeisureStateView.loading());
        }
        if (snap.hasError) {
          final f = snap.error is LeisureException
              ? (snap.error as LeisureException).failure
              : LeisureFailure.other;
          return Scaffold(
              appBar: AppBar(),
              body: LeisureStateView.error(failure: f, onRetry: _reload));
        }
        final e = snap.data!;
        _sessions ??= _loadSessions();
        final photos = e.photos;
        final theme = Theme.of(context);
        return Scaffold(
          bottomNavigationBar: FutureBuilder<List<SessionInfo>>(
            future: _sessions,
            builder: (context, sessions) {
              final session = _session;
              String label;
              if (!e.bookable) {
                label = s.lzUnavailable;
              } else if (session == null) {
                label =
                    '${e.bookingType == BookingType.seatMap ? s.lzChooseSeats : s.lzBook} · ${s.lzFromPrice(formatTenge(e.fromPriceMinor))}';
              } else if (session.free <= 0) {
                label = s.lzFree(0);
              } else {
                label = e.bookingType == BookingType.seatMap
                    ? '${s.lzChooseSeats} · ${s.lzFromPrice(formatTenge(e.fromPriceMinor))}'
                    : '${s.lzChooseTickets} · ${s.lzFromPrice(formatTenge(e.fromPriceMinor))}';
              }
              return PrimaryBar(
                label: label,
                busy: _busy,
                top: _error == null ? null : LeisureErrorBanner(_error!),
                onPressed: e.bookable && session != null && session.free > 0
                    ? () => _continue(e)
                    : null,
              );
            },
          ),
          body: CustomScrollView(slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 280,
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: Colors.white,
              leading: Padding(
                padding: const EdgeInsets.all(6),
                child: CircleAvatar(
                    backgroundColor: Colors.black38,
                    child: BackButton(
                        color: Colors.white,
                        onPressed: () => Navigator.of(context).maybePop())),
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: CircleAvatar(
                    backgroundColor: Colors.black38,
                    child: IconButton(
                      tooltip: s.lzFavorite,
                      onPressed: _toggleFavorite,
                      icon: Icon(
                          _favorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: _favorite
                              ? const Color(0xFFFF6B88)
                              : Colors.white),
                    ),
                  ),
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(fit: StackFit.expand, children: [
                  if (photos.isEmpty)
                    EventPhoto(
                        url: null, category: e.category.code, iconSize: 72)
                  else
                    PageView.builder(
                      controller: _gallery,
                      itemCount: photos.length,
                      onPageChanged: (i) => setState(() => _page = i),
                      itemBuilder: (_, i) => EventPhoto(
                          url: photos[i],
                          category: e.category.code,
                          iconSize: 72),
                    ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                        gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                          Colors.black26,
                          Colors.transparent,
                          Colors.black38
                        ])),
                  ),
                  if (photos.length > 1)
                    Positioned(
                      right: 16,
                      bottom: 40,
                      child: MiniChip('${_page + 1}/${photos.length}'),
                    ),
                ]),
              ),
            ),
            SliverToBoxAdapter(
              child: Transform.translate(
                offset: const Offset(0, -22),
                child: Container(
                  decoration: BoxDecoration(
                      color: theme.scaffoldBackgroundColor,
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(26))),
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Semantics(
                                header: true,
                                child: Text(e.title,
                                    style: theme.textTheme.headlineSmall
                                        ?.copyWith(
                                            fontWeight: FontWeight.w900))),
                            const SizedBox(height: 6),
                            Row(children: [
                              if (e.rating != null) ...[
                                RatingBadge(
                                    rating: e.rating!, count: e.reviewCount),
                                const SizedBox(width: 10)
                              ],
                              Flexible(
                                  child: Text(
                                      e.category.name(
                                          Localizations.localeOf(context)
                                              .languageCode),
                                      style: theme.textTheme.bodyMedium)),
                            ]),
                            const SizedBox(height: 10),
                            _InfoRow(
                                icon: Icons.place_outlined,
                                text: [e.venue.name, e.venue.address]
                                    .where((x) => x.isNotEmpty)
                                    .join(', ')),
                            _InfoRow(
                                icon: Icons.schedule_rounded,
                                text:
                                    '${s.lzDuration}: ${s.lzMinutes(e.durationMinutes)}'),
                            Wrap(spacing: 8, runSpacing: 6, children: [
                              if (e.minAge > 0)
                                MiniChip(s.lzAgeLimit(e.minAge), filled: true),
                              if (e.familyFriendly) MiniChip(s.lzFamilyOnly),
                              MiniChip(
                                  s.lzFromPrice(formatTenge(e.fromPriceMinor)),
                                  filled: true),
                            ]),
                            if (e.demo) ...[
                              const SizedBox(height: 10),
                              Text(s.lzDemoNote,
                                  style: theme.textTheme.bodySmall)
                            ],
                            if (e.manualConfirmation) ...[
                              const SizedBox(height: 10),
                              _Notice(text: s.lzManualConfirm)
                            ],
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: SegmentedButton<int>(
                                showSelectedIcon: false,
                                segments: [
                                  ButtonSegment(
                                      value: 0,
                                      label: Text(s.lzSchedule,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis)),
                                  ButtonSegment(
                                      value: 1,
                                      label: Text(s.lzAbout,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis)),
                                  ButtonSegment(
                                      value: 2,
                                      label: Text(s.lzReviews,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis)),
                                ],
                                selected: {_tab},
                                onSelectionChanged: (v) => setState(() {
                                  _tab = v.first;
                                  if (_tab == 2) {
                                    _reviews ??=
                                        widget.services.api.reviews(e.id);
                                  }
                                }),
                              ),
                            ),
                            const SizedBox(height: 16),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              child: KeyedSubtree(
                                key: ValueKey(_tab),
                                child: switch (_tab) {
                                  0 => _scheduleTab(e),
                                  1 => _aboutTab(e),
                                  _ => _reviewsTab(e),
                                },
                              ),
                            ),
                          ]),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        );
      },
    );
  }

  Widget _scheduleTab(EventDetail e) {
    final s = lzL10n(context);
    return FutureBuilder<List<SessionInfo>>(
      future: _sessions,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SkeletonBox(height: 120, radius: 18);
        }
        if (snap.hasError) {
          final f = snap.error is LeisureException
              ? (snap.error as LeisureException).failure
              : LeisureFailure.other;
          return LeisureStateView.error(
              failure: f,
              onRetry: () => setState(() {
                    _sessions = _loadSessions();
                  }));
        }
        final all = snap.data!;
        if (all.isEmpty) {
          return LeisureStateView.empty(
              title: s.lzNoSessions, icon: Icons.event_busy_rounded);
        }
        final days = <DateTime>{
          for (final x in all)
            DateTime(x.startsAt.year, x.startsAt.month, x.startsAt.day)
        }.toList()
          ..sort();
        final today = _almatyToday();
        final day = days.contains(_day) ? _day! : days.first;
        final onDay = all
            .where((x) =>
                x.startsAt.year == day.year &&
                x.startsAt.month == day.month &&
                x.startsAt.day == day.day)
            .toList();
        final selected =
            _session != null && onDay.any((x) => x.id == _session!.id)
                ? _session
                : null;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            height: 76 *
                (MediaQuery.textScalerOf(context).scale(14) / 14)
                    .clamp(1.0, 2.2),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: days.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final d = days[i];
                final isSel = d == day;
                final theme = Theme.of(context);
                final label = d == today ? s.lzToday : s.weekday(d);
                return Semantics(
                  button: true,
                  selected: isSel,
                  label: s.lzWeekdayDay(d),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => setState(() {
                      _day = d;
                      _session = null;
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 78,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isSel
                            ? theme.colorScheme.primary
                            : theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: isSel
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outlineVariant),
                      ),
                      child: ExcludeSemantics(
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                      color: isSel
                                          ? theme.colorScheme.onPrimary
                                          : null)),
                              const SizedBox(height: 2),
                              Text(s.lzDayMonth(d),
                                  maxLines: 1,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: isSel
                                          ? theme.colorScheme.onPrimary
                                          : null)),
                            ]),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          Text(s.lzSessionTime,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final x in onDay)
              Semantics(
                button: true,
                selected: selected?.id == x.id,
                enabled: x.free > 0,
                label: '${s.lzClock(x.startsAt)}, ${s.lzFree(x.free)}',
                child: ChoiceChip(
                  showCheckmark: false,
                  label: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(s.lzClock(x.startsAt),
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 16)),
                    Text(s.lzFree(x.free),
                        style: Theme.of(context).textTheme.labelSmall),
                  ]),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  selected: selected?.id == x.id,
                  onSelected:
                      x.free > 0 ? (_) => setState(() => _session = x) : null,
                ),
              ),
          ]),
          const SizedBox(height: 16),
          Text(s.lzTickets,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          for (final t in e.ticketTypes)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(t.name),
              subtitle: Text(t.perBooking ? s.lzPerBooking : s.lzPerPerson),
              trailing: Text(formatTenge(t.priceMinor),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
        ]);
      },
    );
  }

  Widget _aboutTab(EventDetail e) {
    final s = lzL10n(context);
    final theme = Theme.of(context);
    Widget block(String title, String body) => body.trim().isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(body, style: theme.textTheme.bodyMedium),
            ]),
          );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      block(s.lzAbout, '${e.description}\n${e.venue.description}'.trim()),
      block(
          s.lzAddress,
          [e.venue.address, e.venue.district]
              .where((x) => x.isNotEmpty)
              .join(', ')),
      Container(
        padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
            color:
                theme.colorScheme.surfaceContainerHighest.withValues(alpha: .5),
            borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          const Icon(Icons.map_outlined),
          const SizedBox(width: 10),
          Expanded(child: Text(s.lzMapSoon, style: theme.textTheme.bodySmall))
        ]),
      ),
      block(s.lzRules, e.venue.rules),
      block(
          s.lzCancelTerms,
          e.venue.cancellationHours == 0
              ? s.lzFreeUntil(s.lzSessionTime)
              : s.lzFreeUntil(
                  '${e.venue.cancellationHours} ${s.lzMinutes(60).split(' ').last}')),
      block(s.lzOrganizer, e.organizer),
      if (e.minAge > 0) block(s.lzAge, s.lzAgeLimit(e.minAge)),
    ]);
  }

  Widget _reviewsTab(EventDetail e) {
    final s = lzL10n(context);
    final theme = Theme.of(context);
    return FutureBuilder<List<Review>>(
      future: _reviews,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SkeletonBox(height: 90, radius: 18);
        }
        if (snap.hasError) {
          final f = snap.error is LeisureException
              ? (snap.error as LeisureException).failure
              : LeisureFailure.other;
          return LeisureStateView.error(
              failure: f,
              onRetry: () => setState(() {
                    _reviews = widget.services.api.reviews(e.id);
                  }));
        }
        final list = snap.data!;
        if (list.isEmpty) {
          return LeisureStateView.empty(
              title: s.lzNoReviews, icon: Icons.rate_review_outlined);
        }
        return Column(children: [
          for (final r in list)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        for (var i = 0; i < 5; i++)
                          Icon(
                              i < r.rating
                                  ? Icons.star_rounded
                                  : Icons.star_border_rounded,
                              size: 18,
                              color: KundePalette.gold),
                        const Spacer(),
                        Text(s.lzDayMonth(r.createdAt),
                            style: theme.textTheme.bodySmall),
                      ]),
                      if (r.body.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(r.body)
                      ],
                    ]),
              ),
            ),
        ]);
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => text.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon,
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
                child:
                    Text(text, style: Theme.of(context).textTheme.bodyMedium)),
          ]),
        );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .tertiaryContainer
                .withValues(alpha: .6),
            borderRadius: BorderRadius.circular(14)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline_rounded, size: 20),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
        ]),
      );
}

class _TicketChoice {
  const _TicketChoice(this.quantities, this.guests);

  final Map<String, int> quantities;
  final int? guests;
}

/// Quantities per ticket type (per-person pricing) or one booking with a guest count (per-booking pricing); prices come from the server.
class _TicketSheet extends StatefulWidget {
  const _TicketSheet({required this.event, required this.session});

  final EventDetail event;
  final SessionInfo session;

  @override
  State<_TicketSheet> createState() => _TicketSheetState();
}

class _TicketSheetState extends State<_TicketSheet> {
  late final Map<String, int> _qty = {
    for (final t in widget.event.ticketTypes) t.id: 0,
  };
  late String _chosen = widget.event.ticketTypes.first.id;
  int _guests = 2;

  int get _limit {
    final byFree = widget.session.free;
    final byEvent = widget.event.maxGuests;
    return byFree < byEvent ? byFree : byEvent;
  }

  int get _count => _qty.values.fold(0, (a, b) => a + b);

  int get _total {
    final e = widget.event;
    if (e.bookingType.perBooking) {
      return e.ticketTypes.firstWhere((t) => t.id == _chosen).priceMinor;
    }
    return [for (final t in e.ticketTypes) t.priceMinor * (_qty[t.id] ?? 0)]
        .fold(0, (a, b) => a + b);
  }

  @override
  void initState() {
    super.initState();
    if (widget.event.bookingType.perBooking &&
        _guests > widget.event.maxGuests) {
      _guests = widget.event.maxGuests;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = lzL10n(context);
    final theme = Theme.of(context);
    final e = widget.event;
    final perBooking = e.bookingType.perBooking;
    final canContinue = perBooking ? true : _count > 0;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(s.lzTicketsFor,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              Text(s.lzWhen(widget.session.startsAt),
                  style: theme.textTheme.bodyMedium),
              const SizedBox(height: 14),
              if (perBooking) ...[
                RadioGroup<String>(
                  groupValue: _chosen,
                  onChanged: (v) => setState(() => _chosen = v ?? _chosen),
                  child: Column(children: [
                    for (final t in e.ticketTypes)
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        value: t.id,
                        title: Text(t.name),
                        secondary: Text(formatTenge(t.priceMinor),
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                      ),
                  ]),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                      child: Text(s.lzGuestsInGroup,
                          style: theme.textTheme.titleSmall)),
                  _Stepper(
                      value: _guests,
                      min: 1,
                      max: e.maxGuests,
                      onChanged: (v) => setState(() => _guests = v)),
                ]),
              ] else
                for (final t in e.ticketTypes)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(children: [
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.name, style: theme.textTheme.titleSmall),
                              Text(formatTenge(t.priceMinor),
                                  style: theme.textTheme.bodySmall),
                            ]),
                      ),
                      _Stepper(
                        value: _qty[t.id] ?? 0,
                        min: 0,
                        max: (_qty[t.id] ?? 0) + (_limit - _count).clamp(0, 99),
                        onChanged: (v) => setState(() => _qty[t.id] = v),
                      ),
                    ]),
                  ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                    child: Text(s.lzTotal, style: theme.textTheme.titleMedium)),
                Text(formatTenge(_total),
                    style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: theme.colorScheme.primary)),
              ]),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: canContinue
                      ? () => Navigator.pop(
                          context,
                          perBooking
                              ? _TicketChoice({_chosen: 1}, _guests)
                              : _TicketChoice({
                                  for (final x in _qty.entries)
                                    if (x.value > 0) x.key: x.value
                                }, null))
                      : null,
                  child: Text(s.lzContinue),
                ),
              ),
            ]),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper(
      {required this.value,
      required this.min,
      required this.max,
      required this.onChanged});

  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton.filledTonal(
          tooltip: '−',
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_rounded),
        ),
        SizedBox(
            width: 36,
            child: Center(
                child: Text('$value',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)))),
        IconButton.filledTonal(
          tooltip: '+',
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_rounded),
        ),
      ]);
}
