import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/localization/kunde_localizations.dart';
import '../../booking/booking_services.dart';
import '../../booking/data/booking_models.dart';
import '../../booking/presentation/bookings_list.dart';
import '../beauty_strings.dart';
import '../beauty_theme.dart';
import '../data/beauty_models.dart';
import 'beauty_home_screen.dart';
import 'beauty_widgets.dart';

/// «Запись подтверждена!»: shown only after the server has confirmed the booking.
class BeautyConfirmedScreen extends StatelessWidget {
  const BeautyConfirmedScreen({
    required this.services,
    required this.record,
    required this.salon,
    super.key,
  });

  final BookingServices services;
  final BookingRecord record;
  final BeautySalon salon;

  static String _stamp(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}${t.month.toString().padLeft(2, '0')}${t.day.toString().padLeft(2, '0')}'
      'T${t.hour.toString().padLeft(2, '0')}${t.minute.toString().padLeft(2, '0')}00';

  /// Google Calendar event with the venue's wall-clock time and zone; opens in the calendar app or the browser.
  Uri get calendarUri => Uri.https('calendar.google.com', '/calendar/render', {
        'action': 'TEMPLATE',
        'text': '${record.serviceName} · ${record.venueName}',
        'dates': '${_stamp(record.start)}/${_stamp(record.end)}',
        'ctz': 'Asia/Almaty',
        'location': record.venueAddress,
        'details': record.bookingNumber ?? '',
      });

  Uri get routeUri => salon.latitude != null && salon.longitude != null
      ? Uri.https('www.google.com', '/maps/dir/', {
          'api': '1',
          'destination': '${salon.latitude},${salon.longitude}',
        })
      : Uri.https('www.google.com', '/maps/search/', {
          'api': '1',
          'query': record.venueAddress,
        });

  Future<void> _open(BuildContext context, Uri uri) async {
    final s = KundeLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened) {
      messenger.showSnackBar(SnackBar(content: Text(s.bCannotOpen)));
    }
  }

  void _done(BuildContext context) {
    final s = KundeLocalizations.of(context);
    final navigator = Navigator.of(context);
    navigator.popUntil((r) => r.settings.name == beautyShellRoute || r.isFirst);
    navigator.push(beautyRoute(Scaffold(
      appBar: AppBar(title: Text(s.bMyBookings)),
      body: BookingsList(services: services, beautyEnabled: true),
    )));
  }

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              children: [
                Center(
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: BeautyColors.success,
                    ),
                    child: const Icon(Icons.check_rounded,
                        color: Colors.white, size: 64),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  s.bConfirmedTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 26, fontWeight: FontWeight.w800),
                ),
                if (record.bookingNumber != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    '№${record.bookingNumber}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: BeautyColors.primary),
                  ),
                ],
                const SizedBox(height: 22),
                Row(
                  children: [
                    const BeautyPhoto(
                        imageUrl: null, icon: Icons.spa_outlined, size: 56),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(record.serviceName,
                              style: const TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w800)),
                          Text(record.venueName,
                              style:
                                  const TextStyle(color: BeautyColors.muted)),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 28, color: BeautyColors.line),
                _Line(Icons.event_outlined, s.bDayTime(record.start)),
                _Line(Icons.place_outlined, record.venueAddress),
                _Line(
                    Icons.person_outline, '${s.bMaster}: ${record.masterName}'),
                if (record.discountPercent != null)
                  _Line(Icons.local_offer_outlined,
                      '${s.bDiscountLine(record.discountPercent!)} · ${s.bMoney(record.priceMinor)}'),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Column(
                children: [
                  _OutlineAction(
                    icon: Icons.event_available_outlined,
                    label: s.bAddToCalendar,
                    onTap: () => _open(context, calendarUri),
                  ),
                  const SizedBox(height: 10),
                  _OutlineAction(
                    icon: Icons.route_outlined,
                    label: s.bRoute,
                    onTap: () => _open(context, routeUri),
                  ),
                  const SizedBox(height: 10),
                  BeautyPrimaryButton(
                    label: s.bDone,
                    onPressed: () => _done(context),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, color: BeautyColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(text,
                  style: const TextStyle(
                      fontSize: 15.5, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}

class _OutlineAction extends StatelessWidget {
  const _OutlineAction(
      {required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          foregroundColor: BeautyColors.primary,
          side: const BorderSide(color: BeautyColors.line),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      );
}
