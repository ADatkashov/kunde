import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../widgets/header_row.dart';
import '../../widgets/status_chip.dart';

class BookingActionBar extends StatelessWidget {
  const BookingActionBar({
    required this.booking,
    required this.busy,
    required this.onAction,
    super.key,
  });
  final PartnerBooking booking;
  final bool busy;
  final void Function(String action) onAction;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final actions = booking.allowedActions;
    if (actions.isEmpty) return const SizedBox.shrink();
    const negative = {'REJECT', 'CANCEL'};
    return Padding(
      padding: const EdgeInsets.only(top: Gap.md),
      child: Wrap(spacing: Gap.sm, runSpacing: Gap.sm, children: [
        for (final a in actions.where((a) => !negative.contains(a)))
          FilledButton(
            onPressed: busy ? null : () => onAction(a),
            child: Text(s.bookingAction(a)),
          ),
        for (final a in actions.where(negative.contains))
          OutlinedButton(
            style: OutlinedButton.styleFrom(
                foregroundColor: context.colors.error,
                side: BorderSide(
                    color: context.colors.error.withValues(alpha: 0.6))),
            onPressed: busy ? null : () => onAction(a),
            child: Text(s.bookingAction(a)),
          ),
      ]),
    );
  }
}

String bookingWhenText(PartnerBooking b, Locale locale, S s) {
  final start = b.startsAt;
  if (start == null) return s.dash;
  final end = b.endsAt;
  final range = end == null
      ? formatTime(start)
      : '${formatTime(start)}–${formatTime(end)}';
  return '${formatDate(start, locale)}, $range';
}

class BookingCard extends StatelessWidget {
  const BookingCard({
    required this.booking,
    required this.busy,
    required this.onOpen,
    required this.onAction,
    super.key,
  });
  final PartnerBooking booking;
  final bool busy;
  final VoidCallback onOpen;
  final void Function(String action) onAction;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final locale = Localizations.localeOf(context);
    final muted = context.text.bodyMedium
        ?.copyWith(color: context.colors.onSurfaceVariant);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(Gap.lg),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            HeaderRow(
              leading: Text(
                  booking.serviceName.isEmpty
                      ? s.bookingDetails
                      : booking.serviceName,
                  style: context.text.titleMedium),
              trailing: StatusChip(
                  label: s.bookingStatus(booking.status),
                  tone: bookingTone(booking.status)),
            ),
            const SizedBox(height: Gap.sm),
            Row(children: [
              Icon(Icons.event_rounded,
                  size: 18, color: context.colors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(bookingWhenText(booking, locale, s),
                    style: context.text.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
            ]),
            if (booking.vehicle != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('${s.vehicleLabel}: ${booking.vehicle}'),
              ),
            if (booking.category == 'CLEANING' &&
                booking.status == 'CONFIRMED' &&
                booking.masterName == null)
              Text(s.bookingUnassigned, style: muted),
            if (booking.masterName != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('${s.bookingMaster}: ${booking.masterName}',
                    style: muted),
              ),
            const SizedBox(height: Gap.sm),
            Text(formatMoney(booking.priceMinor, currency: booking.currency),
                style: context.text.titleMedium?.copyWith(
                    color: context.colors.primary,
                    fontWeight: FontWeight.w700)),
            if (booking.status == 'CANCELLED' && booking.cancelReason != null)
              Padding(
                padding: const EdgeInsets.only(top: Gap.sm),
                child: Text(
                    '${s.bookingCancelReasonTitle}: ${s.reasonText(booking.cancelReason!)}',
                    style: context.text.bodySmall
                        ?.copyWith(color: context.colors.onSurfaceVariant)),
              ),
            BookingActionBar(booking: booking, busy: busy, onAction: onAction),
          ]),
        ),
      ),
    );
  }
}
