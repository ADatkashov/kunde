import 'package:flutter/material.dart';
import 'package:kunde_design/kunde_design.dart';

import '../../core/format.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../widgets/states.dart';
import 'leisure_bookings.dart';
import 'leisure_catalog.dart';
import 'leisure_ops.dart';
import 'leisure_scan.dart';
import 'leisure_strings.dart';

/// Leisure for a partner: overview with real sales and attendance, events and sessions, bookings and QR check-in.
/// OWNER and MANAGER manage the catalogue; STAFF sees bookings and checks tickets in. The server enforces the same split.
class PartnerLeisureScreen extends StatefulWidget {
  const PartnerLeisureScreen(
      {required this.ops, required this.canManage, super.key});

  final LeisureOps ops;
  final bool canManage;

  @override
  State<PartnerLeisureScreen> createState() => _PartnerLeisureScreenState();
}

class _PartnerLeisureScreenState extends State<PartnerLeisureScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.ops.isEvents ? s.evTitle : s.lzTitle),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: s.lzOverview),
            Tab(text: s.lzEvents),
            Tab(text: s.lzBookings),
            Tab(text: s.lzScan)
          ],
        ),
      ),
      body: TabBarView(
          controller: _tabs,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _Overview(
                ops: widget.ops,
                canManage: widget.canManage,
                onCreate: () => _tabs.animateTo(1),
                onScan: () => _tabs.animateTo(3)),
            LeisureCatalog(ops: widget.ops, canManage: widget.canManage),
            LeisureBookings(ops: widget.ops, canManage: widget.canManage),
            LeisureScanner(ops: widget.ops),
          ]),
    );
  }
}

class _Overview extends StatefulWidget {
  const _Overview(
      {required this.ops,
      required this.canManage,
      required this.onCreate,
      required this.onScan});

  final LeisureOps ops;
  final bool canManage;
  final VoidCallback onCreate;
  final VoidCallback onScan;

  @override
  State<_Overview> createState() => _OverviewState();
}

class _OverviewState extends State<_Overview> {
  int _days = 7;
  late Future<Map<String, dynamic>> _stats = widget.ops.stats(_days);
  late Future<List<Map<String, dynamic>>> _upcoming =
      widget.ops.orders('upcoming');

  void _reload() => setState(() {
        _stats = widget.ops.stats(_days);
        _upcoming = widget.ops.orders('upcoming');
      });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: () async {
        _reload();
        await _stats;
      },
      child: ListView(padding: const EdgeInsets.all(Gap.lg), children: [
        Wrap(spacing: Gap.sm, children: [
          for (final d in [1, 7, 30])
            ChoiceChip(
                label: Text(d == 1 ? s.lzDays(1) : s.lzDays(d)),
                selected: _days == d,
                onSelected: (_) {
                  _days = d;
                  _reload();
                }),
        ]),
        const SizedBox(height: Gap.md),
        FutureBuilder<Map<String, dynamic>>(
          future: _stats,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SkeletonBox(height: 180, radius: 16);
            }
            if (snap.hasError) {
              return ErrorView(error: snap.error!, onRetry: _reload);
            }
            final d = snap.data!;
            Widget tile(IconData icon, String label, String value) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(Gap.md),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(icon, color: theme.colorScheme.primary),
                          const SizedBox(height: Gap.sm),
                          Text(value,
                              style: theme.textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w900)),
                          Text(label, style: theme.textTheme.bodySmall),
                        ]),
                  ),
                );
            Widget pair(Widget a, Widget b) => Padding(
                  padding: const EdgeInsets.only(bottom: Gap.md),
                  child: IntrinsicHeight(
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: a),
                          const SizedBox(width: Gap.md),
                          Expanded(child: b),
                        ]),
                  ),
                );
            return Column(children: [
              pair(
                  tile(Icons.payments_outlined, s.lzSales,
                      formatMoney((d['bookedMinor'] as num).toInt())),
                  tile(Icons.confirmation_number_outlined, s.lzOrders,
                      '${d['orders']}')),
              pair(
                  tile(Icons.groups_outlined, s.lzAttendance,
                      '${d['admittedGuests']}'),
                  tile(Icons.event_available_outlined, s.lzUpcomingSessions,
                      '${d['upcomingSessions']}')),
            ]);
          },
        ),
        const SizedBox(height: Gap.lg),
        Row(children: [
          if (widget.canManage)
            Expanded(
              child: FilledButton.tonalIcon(
                  onPressed: widget.onCreate,
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  label: Text(s.lzCreateEvent, textAlign: TextAlign.center)),
            ),
          if (widget.canManage) const SizedBox(width: Gap.md),
          Expanded(
              child: FilledButton.tonalIcon(
                  onPressed: widget.onScan,
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: Text(s.lzScanQr, textAlign: TextAlign.center))),
        ]),
        const SizedBox(height: Gap.xl),
        Text(s.lzNearest,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: Gap.sm),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _upcoming,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SkeletonBox(height: 90, radius: 16);
            }
            if (snap.hasError) {
              return ErrorView(error: snap.error!, onRetry: _reload);
            }
            final rows = snap.data!;
            if (rows.isEmpty) {
              return Padding(
                  padding: const EdgeInsets.all(Gap.lg),
                  child: Text(s.lzNothing));
            }
            return Column(children: [
              for (final o in rows.take(6))
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.event_rounded),
                    title: Text('${o['eventTitle']}',
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                        '${shortWhen('${o['startsAt']}')} · ${s.lzGuests}: ${o['guests']}'),
                    trailing: Text(
                        formatMoney((o['totalMinor'] as num).toInt()),
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
            ]);
          },
        ),
      ]),
    );
  }
}

/// `21.11 19:30` from an API timestamp with the venue offset (the wall clock of the offset is shown, never converted).
String shortWhen(String iso) {
  final m = RegExp(r'^\d{4}-(\d{2})-(\d{2})T(\d{2}):(\d{2})').firstMatch(iso);
  return m == null ? iso : '${m[2]}.${m[1]} ${m[3]}:${m[4]}';
}

Color statusColor(BuildContext context, String status) => switch (status) {
      'PUBLISHED' ||
      'APPROVED' ||
      'CONFIRMED' ||
      'VALID' =>
        context.tones.success,
      'REJECTED' ||
      'BLOCKED' ||
      'CANCELLED' =>
        Theme.of(context).colorScheme.error,
      'PENDING' => KundePalette.gold,
      _ => Theme.of(context).colorScheme.outline,
    };
