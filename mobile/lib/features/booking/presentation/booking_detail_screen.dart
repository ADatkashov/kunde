import 'package:flutter/material.dart';

import 'booking_strings.dart';

import '../../food/presentation/food_widgets.dart';
import '../booking_services.dart';
import '../data/booking_api.dart';
import '../data/booking_models.dart';

/// One booking: details, status and free cancellation before the start.
class BookingDetailScreen extends StatefulWidget {
  const BookingDetailScreen(
      {required this.services,
      required this.bookingId,
      this.initial,
      this.justBooked = false,
      super.key});

  final BookingServices services;
  final String bookingId;
  final BookingRecord? initial;
  final bool justBooked;

  @override
  State<BookingDetailScreen> createState() => _BookingDetailScreenState();
}

class _BookingDetailScreenState extends State<BookingDetailScreen> {
  BookingRecord? _booking;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _booking = widget.initial;
    _load();
  }

  Future<void> _load() async {
    try {
      final booking = await widget.services.api.booking(widget.bookingId);
      if (!mounted) return;
      setState(() {
        _booking = booking;
        _error = null;
      });
    } on BookingException catch (error) {
      if (!mounted || _booking != null) return;
      setState(() => _error = bkL10n(context).bkError(error.failure));
    }
  }

  Future<void> _cancel() async {
    final s = bkL10n(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.bkCancelQuestion),
        content: Text(s.bkCancelBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.bkNo)),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(s.bkCancelBooking)),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final updated = await widget.services.api.cancel(widget.bookingId);
      if (mounted) setState(() => _booking = updated);
    } on BookingException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.bkError(error.failure))));
      _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = bkL10n(context);
    final b = _booking;
    return Scaffold(
      appBar: AppBar(
          title: Text(
              b?.isCleaning == true ? s.bkCleaningTitle : s.bkBookingTitle)),
      body: b == null
          ? (_error != null
              ? FoodStateMessage(
                  icon: Icons.cloud_off_outlined,
                  title: s.bkDetailLoadError,
                  body: _error,
                  onAction: _load)
              : const Center(child: CircularProgressIndicator()))
          : RefreshIndicator(
              onRefresh: _load,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      if (widget.justBooked && b.status == 'CONFIRMED')
                        Card(
                          color: theme.colorScheme.primaryContainer,
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            leading: const Icon(Icons.check_circle_rounded),
                            title: Text(b.isCleaning
                                ? s.bkRequestPlacedTitle
                                : s.bkBookedTitle),
                            subtitle: Text(b.isCleaning
                                ? s.bkRequestPlacedBody
                                : s.bkBookedBody),
                          ),
                        ),
                      _StatusBanner(booking: b),
                      const SizedBox(height: 12),
                      Text(b.venueName, style: theme.textTheme.headlineSmall),
                      Text(b.venueAddress,
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                      const Divider(height: 32),
                      _row(Icons.event_rounded,
                          '${formatDay(b.start)}, ${formatClock(b.start)}–${formatClock(b.end)}'),
                      _row(
                          b.isCleaning
                              ? Icons.cleaning_services_rounded
                              : Icons.content_cut_rounded,
                          '${s.bkCatalogName(b.serviceName)} · ${formatDuration(b.durationMinutes)}'),
                      if (b.isCleaning && b.addressText != null)
                        _row(Icons.location_on_outlined, b.addressText!),
                      if (b.areaSqm != null)
                        _row(Icons.square_foot_outlined,
                            s.bkAreaLine(b.areaSqm!)),
                      _row(
                          Icons.person_outline_rounded,
                          b.isCleaning
                              ? '${s.bkCrew}: ${b.masterName}'
                              : s.bkMasterLine(b.masterName)),
                      _row(Icons.payments_outlined,
                          s.bkPaidOnSite(formatTenge(b.priceMinor))),
                      if (b.comment != null)
                        _row(Icons.chat_bubble_outline_rounded, b.comment!),
                      const SizedBox(height: 16),
                      if (b.cancellable)
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _cancel,
                          icon: const Icon(Icons.close_rounded),
                          label: Text(b.isCleaning
                              ? s.bkCancelRequest
                              : s.bkCancelBooking),
                        ),
                      const SizedBox(height: 12),
                      Text(s.bkDetailDevNote,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _row(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 22),
          const SizedBox(width: 12),
          Expanded(
              child: Text(text, style: Theme.of(context).textTheme.bodyLarge)),
        ]),
      );
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.booking});

  final BookingRecord booking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = bkL10n(context);
    final cancelled = booking.status == 'CANCELLED';
    final done = booking.status == 'COMPLETED';
    return Material(
      color: cancelled
          ? theme.colorScheme.errorContainer
          : done
              ? const Color(0xFFDDF4E2)
              : const Color(0xFFDDEBFF),
      borderRadius: BorderRadius.circular(14),
      child: ListTile(
        leading: Icon(cancelled
            ? Icons.cancel_outlined
            : done
                ? Icons.task_alt_rounded
                : Icons.event_available_rounded),
        title: Text(s.bkStatus(booking.status)),
        subtitle: Text(cancelled
            ? s.bkStatusCancelledHint
            : done
                ? s.bkStatusCompletedHint
                : booking.isCleaning
                    ? s.bkStatusConfirmedHome
                    : s.bkStatusConfirmedHint),
      ),
    );
  }
}
