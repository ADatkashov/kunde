import '../../home_services/presentation/home_service_reviews.dart';
import '../../home_services/presentation/home_service_visit_card.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:kunde_ui/booking_strings.dart';

import '../../food/presentation/food_widgets.dart';
import '../booking_services.dart';
import 'package:kunde_api/booking_api.dart';
import 'package:kunde_models/booking_models.dart';

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
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _booking = widget.initial;
    _load();
    // A request waiting for the partner's answer is refreshed until it is decided.
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      final b = _booking;
      if (b == null) return;
      // A home visit also moves on its own (started, finished by the master), so the screen follows it.
      if (b.status == 'PENDING' ||
          (b.isCleaning &&
              (b.status == 'CONFIRMED' || b.status == 'IN_PROGRESS'))) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
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

  Future<void> _move(BookingRecord booking) async {
    final s = bkL10n(context);
    final almaty = DateTime.now().toUtc().add(const Duration(hours: 5));
    final today = DateTime(almaty.year, almaty.month, almaty.day);
    final date = await showDatePicker(
      context: context,
      firstDate: today,
      lastDate: today.add(const Duration(days: 13)),
      initialDate: today,
    );
    if (!mounted || date == null) return;
    final slots = widget.services.api.slots(
      venueId: booking.venueId!,
      serviceId: booking.serviceId!,
      masterId: booking.masterId!,
      date: date,
    );
    final slot = await showModalBottomSheet<BookingSlot>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: FutureBuilder<List<BookingSlot>>(
          future: slots,
          builder: (context, state) {
            if (state.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final offered = state.data ?? const <BookingSlot>[];
            if (offered.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Text(state.hasError ? s.bkSlotsError : s.bkNoSlots),
              );
            }
            return ListView(
              children: [
                for (final slot in offered)
                  ListTile(
                    title: Text(formatClock(slot.start)),
                    onTap: () => Navigator.of(context).pop(slot),
                  ),
              ],
            );
          },
        ),
      ),
    );
    if (!mounted || slot == null) return;
    setState(() => _busy = true);
    try {
      final moved = await widget.services.api.reschedule(booking, slot);
      if (mounted) setState(() => _booking = moved);
    } on BookingException catch (error) {
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.bkError(error.failure))),
      );
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
                      if (widget.justBooked &&
                          (b.status == 'CONFIRMED' || b.status == 'PENDING'))
                        Card(
                          color: theme.colorScheme.primaryContainer,
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            leading: const Icon(Icons.check_circle_rounded),
                            title: Text(b.isCleaning ||
                                    (b.isHealth && b.status == 'PENDING')
                                ? s.bkRequestPlacedTitle
                                : s.bkBookedTitle),
                            subtitle: Text(b.isCleaning ||
                                    (b.isHealth && b.status == 'PENDING') ||
                                    (b.isHealth && b.status == 'PENDING')
                                ? s.bkRequestPlacedBody
                                : s.bkBookedBody),
                          ),
                        ),
                      _StatusBanner(booking: b),
                      if (b.isCleaning &&
                          (b.status == 'CONFIRMED' ||
                              b.status == 'IN_PROGRESS'))
                        HomeServiceVisitCard(
                          key: ValueKey('visit-${b.id}-${b.status}'),
                          load: () async => (await widget.services.auth
                                  .authorizedJson('GET',
                                      'home-services/bookings/${b.id}/visit'))
                              as Map<String, dynamic>,
                        ),
                      if (b.isCleaning && b.status == 'COMPLETED')
                        HomeServiceReviewCard(
                          key: ValueKey('review-${b.id}'),
                          auth: widget.services.auth,
                          bookingId: b.id,
                        ),
                      if (b.isHealth)
                        SelectableText(b.id, style: theme.textTheme.bodySmall),
                      const SizedBox(height: 12),
                      Text(b.venueName, style: theme.textTheme.headlineSmall),
                      Text(b.venueAddress,
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                      const Divider(height: 32),
                      _row(Icons.event_rounded,
                          '${b.isHealth ? MaterialLocalizations.of(context).formatMediumDate(b.start) : formatDay(b.start)}, ${formatClock(b.start)}–${formatClock(b.end)}'),
                      _row(
                          switch (b.category) {
                            'HEALTH' => Icons.health_and_safety_outlined,
                            'CLEANING' => Icons.cleaning_services_rounded,
                            _ => Icons.content_cut_rounded,
                          },
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
                              : b.isHealth
                                  ? s.healthSpecialistLine(b.masterName)
                                  : s.bkMasterLine(b.masterName)),
                      _row(
                          Icons.payments_outlined,
                          b.paymentMethod == 'TEST_CARD'
                              ? s.healthText(
                                  'Тестовый платёж · ${formatTenge(b.priceMinor)}',
                                  'Сынақ төлемі · ${formatTenge(b.priceMinor)}',
                                  'Test payment · ${formatTenge(b.priceMinor)}')
                              : s.bkPaidOnSite(formatTenge(b.priceMinor))),
                      if (b.comment != null)
                        _row(Icons.chat_bubble_outline_rounded, b.comment!),
                      const SizedBox(height: 16),
                      if (b.reschedulable &&
                          b.venueId != null &&
                          b.serviceId != null &&
                          b.masterId != null)
                        OutlinedButton.icon(
                          onPressed: _busy ? null : () => _move(b),
                          icon: const Icon(Icons.edit_calendar_outlined),
                          label: Text(s.healthText('Перенести запись',
                              'Жазылуды ауыстыру', 'Reschedule')),
                        ),
                      if (b.cancellable)
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _cancel,
                          icon: const Icon(Icons.close_rounded),
                          label: Text(b.isCleaning
                              ? s.bkCancelRequest
                              : s.bkCancelBooking),
                        ),
                      const SizedBox(height: 12),
                      Text(
                          b.isHealth
                              ? s.healthText(
                                  'Синтетическая запись для проверки сервиса',
                                  'Сервисті тексеруге арналған синтетикалық жазба',
                                  'Synthetic appointment for testing the service')
                              : s.bkDetailDevNote,
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
            ? (booking.cancelReason != null && booking.cancelledBy == 'PARTNER'
                ? '${s.bkStatusCancelledHint}\n${s.bkCancelReason(booking.cancelReason!)}'
                : s.bkStatusCancelledHint)
            : booking.status == 'PENDING'
                ? s.bkStatusPendingHint
                : done
                    ? s.bkStatusCompletedHint
                    : booking.isCleaning
                        ? s.bkStatusConfirmedHome
                        : s.bkStatusConfirmedHint),
      ),
    );
  }
}
