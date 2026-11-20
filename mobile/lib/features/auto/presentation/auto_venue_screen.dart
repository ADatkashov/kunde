import 'package:flutter/material.dart';

import '../auto_services.dart';
import '../data/auto_api.dart';
import '../data/auto_models.dart';
import 'auto_booking_flow_screen.dart';
import 'auto_strings.dart';
import 'auto_widgets.dart';

/// Station / car wash card: address, services with price kind and conditions.
class AutoVenueScreen extends StatefulWidget {
  const AutoVenueScreen(
      {required this.services, required this.venueId, super.key});

  final AutoServices services;
  final String venueId;

  @override
  State<AutoVenueScreen> createState() => _AutoVenueScreenState();
}

class _AutoVenueScreenState extends State<AutoVenueScreen> {
  late Future<AutoVenueDetail> _detail =
      widget.services.api.venue(widget.venueId);

  @override
  Widget build(BuildContext context) {
    final s = auL10n(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.auTitle)),
      body: FutureBuilder<AutoVenueDetail>(
        future: _detail,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const AutoStateView.loading();
          }
          if (snap.hasError) {
            final f = snap.error is AutoException
                ? (snap.error as AutoException).failure
                : AutoFailure.other;
            return AutoStateView.error(
                error: f,
                onRetry: () => setState(
                    () => _detail = widget.services.api.venue(widget.venueId)));
          }
          final d = snap.data!;
          final available = d.services.where((x) => x.available).toList();
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Text(d.venue.name, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(d.venue.addressText, style: theme.textTheme.bodyMedium),
                if (d.venue.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(d.venue.description),
                ],
                const SizedBox(height: 16),
                Text(s.auServices, style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                if (available.isEmpty) Text(s.auNoServices),
                for (final svc in available)
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                            color: theme.colorScheme.outlineVariant)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(svc.name, style: theme.textTheme.titleMedium),
                            if (svc.description.isNotEmpty)
                              Text(svc.description),
                            const SizedBox(height: 6),
                            Text(
                                svc.priceKind == 'FIXED'
                                    ? formatTenge(svc.priceMinor)
                                    : s.auFrom(formatTenge(svc.priceMinor)),
                                style: theme.textTheme.titleSmall),
                            Text(s.auPriceKind(svc.priceKind),
                                style: theme.textTheme.bodySmall),
                            Text(
                                s.auDuration(
                                    formatDuration(svc.durationMinutes)),
                                style: theme.textTheme.bodySmall),
                            if (svc.conditions.isNotEmpty)
                              Text(svc.conditions,
                                  style: theme.textTheme.bodySmall),
                            const SizedBox(height: 8),
                            Align(
                                alignment: Alignment.centerRight,
                                child: Semantics(
                                    identifier:
                                        'auto-book-${d.services.indexOf(svc)}',
                                    child: FilledButton(
                                        onPressed: d.venue.open
                                            ? () => Navigator.of(context).push(
                                                MaterialPageRoute<void>(
                                                    builder: (_) =>
                                                        AutoBookingFlowScreen(
                                                            services:
                                                                widget.services,
                                                            venue: d.venue,
                                                            service: svc)))
                                            : null,
                                        child: Text(s.auBook)))),
                          ]),
                    ),
                  ),
              ]),
            ),
          );
        },
      ),
    );
  }
}
