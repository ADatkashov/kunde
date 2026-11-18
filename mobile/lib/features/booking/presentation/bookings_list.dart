import 'package:flutter/material.dart';

import 'booking_strings.dart';

import '../../food/presentation/food_widgets.dart';
import '../booking_services.dart';
import '../data/booking_api.dart';
import '../data/booking_models.dart';
import 'booking_detail_screen.dart';
import 'services_home_screen.dart';

/// History of the signed-in customer's bookings, restored from the server on every open.
class BookingsList extends StatefulWidget {
  const BookingsList({required this.services, super.key});

  final BookingServices services;

  @override
  State<BookingsList> createState() => _BookingsListState();
}

class _BookingsListState extends State<BookingsList> {
  late Future<List<BookingRecord>> _bookings = widget.services.api.bookings();

  Future<void> _refresh() async {
    final next = widget.services.api.bookings();
    setState(() {
      _bookings = next;
    });
    try {
      await next;
    } catch (_) {}
  }

  Future<void> _open(BookingRecord b) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => BookingDetailScreen(
            services: widget.services, bookingId: b.id, initial: b)));
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final s = bkL10n(context);
    return FutureBuilder<List<BookingRecord>>(
      future: _bookings,
      builder: (context, state) {
        if (state.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.hasError) {
          final error = state.error;
          return FoodStateMessage(
              icon: Icons.cloud_off_outlined,
              title: s.bkLoadListError,
              body: error is BookingException ? s.bkError(error.failure) : null,
              onAction: _refresh);
        }
        final all = state.data!;
        if (all.isEmpty) {
          return FoodStateMessage(
            icon: Icons.event_busy_outlined,
            title: s.bkEmptyTitle,
            body: s.bkEmptyBody,
            actionLabel: s.bkChooseService,
            onAction: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => ServicesHomeScreen(services: widget.services))),
          );
        }
        final upcoming =
            all.where((b) => b.cancellable).toList().reversed.toList();
        final history = all.where((b) => !b.cancellable).toList();
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              if (upcoming.isNotEmpty) ...[
                Text(s.bkUpcoming,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                for (final b in upcoming)
                  _BookingCard(booking: b, onTap: () => _open(b)),
                const SizedBox(height: 16),
              ],
              if (history.isNotEmpty) ...[
                Text(s.bkHistory,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                for (final b in history)
                  _BookingCard(booking: b, onTap: () => _open(b)),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.booking, required this.onTap});

  final BookingRecord booking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = bkL10n(context);
    final colors = theme.colorScheme;
    final (chipColor, chipInk) = switch (booking.status) {
      'CANCELLED' => (colors.errorContainer, colors.onErrorContainer),
      'COMPLETED' => (colors.tertiaryContainer, colors.onTertiaryContainer),
      _ => (colors.secondaryContainer, colors.onSecondaryContainer),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: colors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: theme.colorScheme.outlineVariant)),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(
                    booking.isCleaning
                        ? Icons.cleaning_services_outlined
                        : Icons.content_cut,
                    color: colors.primary,
                    size: 20),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(booking.venueName,
                        style: theme.textTheme.titleMedium)),
                const SizedBox(width: 8),
                Flexible(
                    child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: chipColor,
                      borderRadius: BorderRadius.circular(999)),
                  child: Text(s.bkStatus(booking.status),
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: chipInk)),
                )),
              ]),
              const SizedBox(height: 6),
              Text(
                  '${s.bkCatalogName(booking.serviceName)} · ${booking.masterName}'),
              if (booking.isCleaning && booking.addressText != null)
                Text(booking.addressText!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: Text(
                      '${formatDay(booking.start)}, ${formatClock(booking.start)}',
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ),
                const SizedBox(width: 8),
                Text(formatTenge(booking.priceMinor),
                    style: theme.textTheme.titleSmall),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
