import 'package:flutter/material.dart';

import '../../app/ops_store.dart';
import '../../core/format.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../widgets/header_row.dart';
import '../../widgets/status_chip.dart';
import 'booking_actions.dart';
import 'booking_card.dart';

class BookingDetailsPage extends StatelessWidget {
  const BookingDetailsPage(
      {required this.store, required this.bookingId, super.key});
  final OpsStore store;
  final String bookingId;

  PartnerBooking? _find() {
    for (final list in [
      store.bookingRequests.data,
      store.bookingUpcoming.data,
      store.bookingHistory.data
    ]) {
      for (final b in list ?? const <PartnerBooking>[]) {
        if (b.id == bookingId) return b;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final b = _find();
        return Scaffold(
          appBar: AppBar(title: Text(s.bookingDetails)),
          body: b == null
              ? const SizedBox.shrink()
              : _Body(booking: b, store: store),
          bottomNavigationBar: b == null || b.allowedActions.isEmpty
              ? null
              : SafeArea(
                  child: Padding(
                    padding:
                        const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.md),
                    child: Row(children: [
                      Flexible(
                        child: BookingActionBar(
                          booking: b,
                          busy: store.isBusy(b.id),
                          onAction: (a) =>
                              performBookingAction(context, store, b, a),
                        ),
                      ),
                    ]),
                  ),
                ),
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.booking, required this.store});
  final PartnerBooking booking;
  final OpsStore store;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final locale = Localizations.localeOf(context);
    final text = context.text;
    final muted =
        text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant);
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 4, child: Text(label, style: muted)),
            Expanded(
                flex: 6,
                child: Text(value,
                    textAlign: TextAlign.end, style: text.bodyMedium)),
          ]),
        );
    return ListView(padding: const EdgeInsets.all(Gap.lg), children: [
      HeaderRow(
        leading: StatusChip(
            label: s.bookingStatus(booking.status),
            tone: bookingTone(booking.status)),
        trailing: Text(
            formatMoney(booking.priceMinor, currency: booking.currency),
            style: text.headlineSmall?.copyWith(
                color: context.colors.primary, fontWeight: FontWeight.w700)),
      ),
      const SizedBox(height: Gap.lg),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(Gap.lg),
          child: Column(children: [
            row(s.bookingService, booking.serviceName),
            row(s.bookingWhen, bookingWhenText(booking, locale, s)),
            if (booking.durationMinutes > 0)
              row(s.durationLabel, s.minutesShort(booking.durationMinutes)),
            if (booking.vehicle != null) row(s.vehicleLabel, booking.vehicle!),
            if (booking.priceKind != null && booking.priceKind != 'FIXED')
              row(s.priceKindLabel, s.priceKind(booking.priceKind!)),
            if (booking.finalPriceMinor != null)
              row(
                  s.finalPriceLabel,
                  '${formatMoney(booking.finalPriceMinor!, currency: booking.currency)}'
                  '${booking.priceApproval == null ? '' : ' · ${s.priceApproval(booking.priceApproval!)}'}'),
            if (booking.masterName != null)
              row(s.bookingMaster, booking.masterName!),
            if (booking.venueName.isNotEmpty)
              row(s.bookingPlace, booking.venueName),
            if (booking.addressText != null)
              row(s.bookingAddress, booking.addressText!),
            if (booking.comment != null)
              row(s.bookingComment, booking.comment!),
            if (booking.createdAt != null)
              row(s.requestedAt, formatDateTime(booking.createdAt!, locale)),
            if (booking.cancelReason != null)
              row(s.bookingCancelReasonTitle,
                  s.reasonText(booking.cancelReason!)),
          ]),
        ),
      ),
      if (booking.timeline.isNotEmpty) ...[
        const SizedBox(height: Gap.md),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Gap.lg),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.history, style: text.titleMedium),
              const SizedBox(height: Gap.sm),
              for (final e in booking.timeline)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.circle,
                            size: 10, color: context.colors.primary),
                        const SizedBox(width: Gap.sm),
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    '${s.bookingStatus(e.status)} · ${s.actorName(e.actor)}',
                                    style: text.bodyMedium),
                                if (e.at != null)
                                  Text(formatDateTime(e.at!, locale),
                                      style: text.bodySmall?.copyWith(
                                          color:
                                              context.colors.onSurfaceVariant)),
                                if (e.reason != null)
                                  Text(s.reasonText(e.reason!),
                                      style: text.bodySmall),
                              ]),
                        ),
                      ]),
                ),
            ]),
          ),
        ),
      ],
    ]);
  }
}
