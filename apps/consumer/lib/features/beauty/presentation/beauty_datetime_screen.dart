import 'dart:async';

import 'package:flutter/material.dart';

import 'package:kunde_localization/kunde_localizations.dart';
import '../../booking/booking_services.dart';
import 'package:kunde_api/booking_api.dart';
import 'package:kunde_models/booking_models.dart';
import 'package:kunde_ui/booking_strings.dart';
import 'package:kunde_ui/beauty_strings.dart';
import 'package:kunde_ui/beauty_theme.dart';
import 'package:kunde_models/beauty_models.dart';
import 'beauty_checkout_screen.dart';
import 'package:kunde_ui/beauty_support.dart';
import 'package:kunde_ui/beauty_widgets.dart';

/// «Выбор даты и времени»: calendar, real free slots from the server, «Продолжить».
class BeautyDateTimeScreen extends StatefulWidget {
  const BeautyDateTimeScreen({
    required this.services,
    required this.favorites,
    required this.detail,
    required this.master,
    super.key,
  });

  final BookingServices services;
  final BeautyFavorites favorites;
  final BeautyServiceDetail detail;

  /// Null = any master: every start time then carries a concrete master.
  final BeautyMaster? master;

  @override
  State<BeautyDateTimeScreen> createState() => _BeautyDateTimeScreenState();
}

class _BeautyDateTimeScreenState extends State<BeautyDateTimeScreen> {
  /// The booking horizon of the server is 14 days including today.
  static const _horizonDays = 14;

  late final DateTime _first = _today();
  late final DateTime _last =
      _first.add(const Duration(days: _horizonDays - 1));
  late DateTime _month = DateTime(_first.year, _first.month);
  late DateTime _selected = _first;
  List<BookingSlot>? _slots;
  Object? _error;
  BookingSlot? _slot;
  int _generation = 0;

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadSlots());
  }

  Future<void> _loadSlots() async {
    final generation = ++_generation;
    setState(() {
      _slots = null;
      _error = null;
      _slot = null;
    });
    try {
      final slots = await widget.services.api.slots(
        venueId: widget.detail.salon.id,
        serviceId: widget.detail.service.id,
        masterId: widget.master?.id,
        date: _selected,
      );
      if (!mounted || generation != _generation) return;
      setState(() => _slots = slots);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = error);
    }
  }

  void _select(DateTime day) {
    setState(() => _selected = day);
    unawaited(_loadSlots());
  }

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.bPickDateTime)),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                BeautyCalendar(
                  month: _month,
                  selected: _selected,
                  first: _first,
                  last: _last,
                  onSelect: _select,
                  onMonthChanged: (m) => setState(() => _month = m),
                ),
                BeautySectionHeader(s.bAvailableTime),
                _slotGrid(s),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: BeautyPrimaryButton(
                label: s.bContinue,
                onPressed: _slot == null
                    ? null
                    : () => Navigator.of(context).push(beautyRoute(
                          BeautyCheckoutScreen(
                            services: widget.services,
                            favorites: widget.favorites,
                            detail: widget.detail,
                            slot: _slot!,
                          ),
                        )),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _slotGrid(KundeLocalizations s) {
    if (_error != null) {
      final message = _error is BookingException
          ? s.bkError((_error as BookingException).failure)
          : s.bLoadFailed;
      return Column(
        children: [
          Text(message),
          TextButton(onPressed: _loadSlots, child: Text(s.retry)),
        ],
      );
    }
    final slots = _slots;
    if (slots == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (slots.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child:
            Text(s.bNoSlots, style: const TextStyle(color: BeautyColors.muted)),
      );
    }
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.2,
      children: [
        for (final slot in slots)
          BeautyTimeSlot(
            label: s.bTime(slot.start),
            selected: _slot?.startsAtIso == slot.startsAtIso,
            onTap: () => setState(() => _slot = slot),
          ),
      ],
    );
  }
}
