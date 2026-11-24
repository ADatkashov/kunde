import 'package:flutter/material.dart';

import 'package:kunde_localization/kunde_localizations.dart';
import '../../booking/booking_services.dart';
import 'package:kunde_api/booking_api.dart';
import 'package:kunde_models/booking_models.dart';
import 'package:kunde_ui/booking_strings.dart';
import 'package:kunde_ui/beauty_strings.dart';
import 'package:kunde_ui/beauty_theme.dart';
import 'package:kunde_models/beauty_models.dart';
import 'beauty_confirmed_screen.dart';
import 'package:kunde_ui/beauty_support.dart';
import 'package:kunde_ui/beauty_widgets.dart';

/// «Оформление записи»: summary, payment method, total and the final confirmation.
///
/// Online payment is not connected yet (DEV pilot): the customer pays at the salon, and the screen says so.
/// The server recomputes the price (promotion included) and refuses a booking whose expected price differs.
class BeautyCheckoutScreen extends StatefulWidget {
  const BeautyCheckoutScreen({
    required this.services,
    required this.favorites,
    required this.detail,
    required this.slot,
    super.key,
  });

  final BookingServices services;
  final BeautyFavorites favorites;
  final BeautyServiceDetail detail;
  final BookingSlot slot;

  @override
  State<BeautyCheckoutScreen> createState() => _BeautyCheckoutScreenState();
}

class _BeautyCheckoutScreenState extends State<BeautyCheckoutScreen> {
  /// One key per checkout attempt: a retry after a lost response never creates a second booking.
  final String _key = BookingApi.newIdempotencyKey();
  bool _busy = false;
  String? _error;

  int get _list => widget.detail.service.priceMinor;
  int? get _discount => widget.detail.salon.discountPercent;
  int get _total =>
      _discount == null ? _list : _list - (_list * _discount! / 100).round();

  Future<void> _confirm() async {
    final s = KundeLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final record = await widget.services.api.book(
        venueId: widget.detail.salon.id,
        serviceId: widget.detail.service.id,
        masterId: widget.slot.masterId,
        startsAtIso: widget.slot.startsAtIso,
        expectedPriceMinor: _total,
        idempotencyKey: _key,
      );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(beautyRoute(
        BeautyConfirmedScreen(
          services: widget.services,
          record: record,
          salon: widget.detail.salon,
        ),
      ));
    } on BookingException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = s.bkError(error.failure);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    final service = widget.detail.service;
    final salon = widget.detail.salon;
    return Scaffold(
      appBar: AppBar(title: Text(s.bCheckoutTitle)),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const BeautyStepper(current: 2),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const BeautyPhoto(
                        imageUrl: null, icon: Icons.spa_outlined, size: 64),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(service.name,
                              style: const TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 2),
                          Text(
                            s.bFromPrice(service.priceMinor,
                                from: service.priceFrom),
                            style: const TextStyle(color: BeautyColors.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 28, color: BeautyColors.line),
                _Row(
                    icon: Icons.storefront_outlined,
                    label: s.bSalon,
                    value: salon.name),
                _Row(
                    icon: Icons.event_outlined,
                    label: s.bDateTimeRow,
                    value: s.bDayTime(widget.slot.start)),
                _Row(
                    icon: Icons.person_outline,
                    label: s.bMaster,
                    value: widget.slot.masterName),
                _Row(
                    icon: Icons.schedule,
                    label: s.bDuration(service.durationMinutes),
                    value: ''),
                const Divider(height: 28, color: BeautyColors.line),
                Row(
                  children: [
                    Expanded(
                      child: Text(s.bPaymentMethod,
                          style: const TextStyle(fontSize: 15)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: BeautyColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: BeautyColors.line),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.storefront,
                              size: 18, color: BeautyColors.primary),
                          const SizedBox(width: 6),
                          Text(s.bPayOnSite,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(s.bPayDevNote,
                    style: const TextStyle(
                        fontSize: 12.5, color: BeautyColors.muted)),
                const Divider(height: 28, color: BeautyColors.line),
                if (_discount != null) ...[
                  Row(
                    children: [
                      Expanded(child: Text(s.bDiscountLine(_discount!))),
                      Text('−${s.bMoney(_list - _total)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: BeautyColors.success)),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    Expanded(
                      child: Text(s.bTotal,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w800)),
                    ),
                    Text(s.bMoney(_total),
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w800)),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(_error!,
                      style: const TextStyle(color: BeautyColors.error)),
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: BeautyPrimaryButton(
                label: s.bConfirm(s.bMoney(_total)),
                loading: _busy,
                onPressed: _confirm,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, color: BeautyColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 15,
                      color: value.isEmpty
                          ? BeautyColors.text
                          : BeautyColors.muted)),
            ),
            if (value.isNotEmpty)
              Flexible(
                child: Text(value,
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
              ),
          ],
        ),
      );
}
