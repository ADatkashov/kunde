import 'package:flutter/material.dart';

import '../auto_services.dart';
import '../data/auto_api.dart';
import 'package:kunde_models/auto_models.dart';
import 'auto_booking_detail_screen.dart';
import 'auto_strings.dart';
import 'auto_widgets.dart';

/// My bookings: active ones first, then the service history.
class AutoBookingsScreen extends StatefulWidget {
  const AutoBookingsScreen({required this.services, super.key});

  final AutoServices services;

  @override
  State<AutoBookingsScreen> createState() => _AutoBookingsScreenState();
}

class _AutoBookingsScreenState extends State<AutoBookingsScreen> {
  late Future<List<AutoBookingRecord>> _bookings =
      widget.services.api.bookings();

  void _reload() => setState(() {
        _bookings = widget.services.api.bookings();
      });

  @override
  Widget build(BuildContext context) {
    final s = auL10n(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.auMyBookings)),
      body: FutureBuilder<List<AutoBookingRecord>>(
        future: _bookings,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const AutoStateView.loading();
          }
          if (snap.hasError) {
            final f = snap.error is AutoException
                ? (snap.error as AutoException).failure
                : AutoFailure.other;
            return AutoStateView.error(error: f, onRetry: _reload);
          }
          final all = snap.data!;
          if (all.isEmpty) {
            return AutoStateView.empty(emptyTitle: s.auNoBookings);
          }
          final active = all.where((b) => b.active).toList();
          final history = all.where((b) => !b.active).toList();
          Widget tile(AutoBookingRecord b) => Card(
                child: ListTile(
                  title: Text(b.serviceName),
                  subtitle: Text(
                      '${b.venueName}\n${formatDay(b.startsAt)}, ${formatClock(b.startsAt)} · ${b.vehicle}\n${s.auStatus(b.status)}'),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => AutoBookingDetailScreen(
                            services: widget.services,
                            bookingId: b.id,
                            initial: b)));
                    _reload();
                  },
                ),
              );
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              if (active.isNotEmpty) ...[
                Text(s.auActive, style: theme.textTheme.titleLarge),
                for (final b in active) tile(b),
                const SizedBox(height: 16),
              ],
              if (history.isNotEmpty) ...[
                Text(s.auHistory, style: theme.textTheme.titleLarge),
                for (final b in history) tile(b),
              ],
            ]),
          );
        },
      ),
    );
  }
}
