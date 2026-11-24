import 'package:flutter/material.dart';

import '../../core/error_text.dart';
import '../../core/format.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../widgets/states.dart';
import 'leisure_ops.dart';
import 'leisure_screen.dart' show shortWhen, statusColor;
import 'leisure_strings.dart';

/// Bookings of the partner's events: requests waiting for confirmation, upcoming and history. Customers appear only as a short reference
/// and a guest count; no contact data is returned by the server.
class LeisureBookings extends StatefulWidget {
  const LeisureBookings(
      {required this.ops, required this.canManage, super.key});

  final LeisureOps ops;
  final bool canManage;

  @override
  State<LeisureBookings> createState() => _LeisureBookingsState();
}

class _LeisureBookingsState extends State<LeisureBookings> {
  String _scope = 'requests';
  late Future<List<Map<String, dynamic>>> _rows = widget.ops.orders(_scope);
  String? _busyId;

  void _reload() => setState(() {
        _rows = widget.ops.orders(_scope);
      });

  Future<void> _act(Map<String, dynamic> order, String action) async {
    final s = S.of(context);
    String? reason;
    if (action != 'CONFIRM') {
      final c = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(action == 'REJECT' ? s.lzReject : s.lzCancel),
          content: TextField(
              controller: c,
              decoration: InputDecoration(labelText: s.lzReason)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(s.lzClose)),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(action == 'REJECT' ? s.lzReject : s.lzCancel)),
          ],
        ),
      );
      reason = c.text.trim();
      c.dispose();
      if (ok != true) return;
    }
    setState(() => _busyId = '${order['id']}');
    try {
      await widget.ops.orderAction('${order['id']}', action, reason: reason);
      if (mounted) _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(errorText(s, e))));
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: SegmentedButton<String>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
                value: 'requests',
                label: Text(s.lzRequests,
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
            ButtonSegment(
                value: 'upcoming',
                label: Text(s.lzUpcoming,
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
            ButtonSegment(
                value: 'history',
                label: Text(s.lzHistory,
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
          selected: {_scope},
          onSelectionChanged: (v) {
            _scope = v.first;
            _reload();
          },
        ),
      ),
      Expanded(
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _rows,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SkeletonList(count: 3);
            }
            if (snap.hasError) {
              return ErrorView(error: snap.error!, onRetry: _reload);
            }
            final rows = snap.data!;
            return RefreshIndicator(
              onRefresh: () async {
                _reload();
                await _rows;
              },
              child: rows.isEmpty
                  ? ListView(children: [
                      Padding(
                          padding: const EdgeInsets.all(Gap.xxl),
                          child: Center(child: Text(s.lzNothing)))
                    ])
                  : ListView.builder(
                      padding:
                          const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.xl),
                      itemCount: rows.length,
                      itemBuilder: (_, i) {
                        final o = rows[i];
                        final status = '${o['status']}';
                        final payment = o['payment'] as Map<String, dynamic>?;
                        return Card(
                          margin: const EdgeInsets.only(bottom: Gap.md),
                          child: Padding(
                            padding: const EdgeInsets.all(Gap.md),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Expanded(
                                        child: Text('${o['eventTitle']}',
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.titleSmall
                                                ?.copyWith(
                                                    fontWeight:
                                                        FontWeight.w800))),
                                    Text(s.lzStatus(status),
                                        style: TextStyle(
                                            color: statusColor(context, status),
                                            fontWeight: FontWeight.w800)),
                                  ]),
                                  Text(
                                      '${shortWhen('${o['startsAt']}')} · #${o['reference']} · ${s.lzGuests}: ${o['guests']}',
                                      style: theme.textTheme.bodySmall),
                                  Text(
                                      '${formatMoney((o['totalMinor'] as num).toInt())} · ${o['paymentMethod'] == 'TEST_CARD' ? s.lzPaymentTest : s.lzPaymentSite}${(payment?['refundedMinor'] as num? ?? 0) > 0 ? ' · ${s.lzRefund}' : ''}',
                                      style: theme.textTheme.bodySmall),
                                  if (o['cancelReason'] != null)
                                    Text('${o['cancelReason']}',
                                        style: theme.textTheme.bodySmall),
                                  if (status == 'PENDING' ||
                                      (status == 'CONFIRMED' &&
                                          widget.canManage &&
                                          _scope != 'history')) ...[
                                    const SizedBox(height: Gap.sm),
                                    Wrap(spacing: Gap.sm, children: [
                                      if (status == 'PENDING')
                                        FilledButton(
                                            onPressed: _busyId == null
                                                ? () => _act(o, 'CONFIRM')
                                                : null,
                                            child: Text(s.lzConfirm)),
                                      if (status == 'PENDING')
                                        OutlinedButton(
                                            onPressed: _busyId == null
                                                ? () => _act(o, 'REJECT')
                                                : null,
                                            child: Text(s.lzReject)),
                                      if (status == 'CONFIRMED')
                                        OutlinedButton(
                                            onPressed: _busyId == null
                                                ? () => _act(o, 'CANCEL')
                                                : null,
                                            child: Text(s.lzCancel)),
                                    ]),
                                  ],
                                ]),
                          ),
                        );
                      },
                    ),
            );
          },
        ),
      ),
    ]);
  }
}
