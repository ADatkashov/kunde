import 'dart:math';

import 'package:flutter/material.dart';

import 'package:kunde_api/booking_api.dart';
import 'package:kunde_api/home_services_api.dart';
import 'package:kunde_maps/kunde_maps.dart';
import 'package:kunde_maps_sdk/kunde_maps_sdk.dart' show GeoPoint;
import 'package:kunde_models/booking_models.dart';
import 'package:kunde_ui/ride_strings.dart';

import '../../booking/booking_services.dart';
import '../../booking/presentation/booking_detail_screen.dart';
import 'home_services_offers_screen.dart' show formatKzt, priceLabel;
import 'home_services_widgets.dart';

/// Order of one published offer: date → slot → address → itemised server price → booking. The price the customer saw
/// (`expectedPriceMinor`) is checked by the server again, so a changed tariff can never be charged silently.
class HomeServiceOrderScreen extends StatefulWidget {
  const HomeServiceOrderScreen({
    required this.offer,
    required this.services,
    required this.api,
    this.initialAreaSqm,
    this.initialUrgent = false,
    this.maps,
    super.key,
  });

  /// What the customer already entered on the offer card, so the price they saw is the price they order.
  final int? initialAreaSqm;
  final bool initialUrgent;

  final HomeServiceOffer offer;
  final BookingServices services;
  final HomeServicesCatalog api;

  /// The map for picking the address; tests inject one. Without it a map is opened on demand (and closed after the pick).
  final KundeMaps? maps;

  @override
  State<HomeServiceOrderScreen> createState() => _HomeServiceOrderScreenState();
}

class _HomeServiceOrderScreenState extends State<HomeServiceOrderScreen> {
  final _address = TextEditingController();
  late final _area = TextEditingController(
    text: widget.initialAreaSqm?.toString() ?? '',
  );
  final _comment = TextEditingController();
  final String _key = _newKey();
  late final DateTime _today = DateTime.now();
  late DateTime _date = _today;
  late Future<List<BookingSlot>> _slots = _loadSlots();
  BookingSlot? _slot;
  late bool _urgent = widget.initialUrgent;
  bool _touched = false;
  bool _busy = false;
  String? _error;
  Future<HomeServiceQuote>? _quote;

  /// The point of the address picked on the map; cleared as soon as the text is edited by hand (it would no longer match).
  double? _lat;
  double? _lng;
  String? _pickedText;

  static String _newKey() {
    final r = Random.secure();
    return List.generate(
      16,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  bool get _perSqm => widget.offer.areaBased;
  int? get _areaValue => int.tryParse(_area.text.trim());
  bool get _addressOk => _address.text.trim().length >= 5;

  Future<List<BookingSlot>> _loadSlots() => widget.services.api.slots(
        venueId: widget.offer.venueId,
        serviceId: widget.offer.serviceId,
        date: _date,
      );

  void _requote() {
    final slot = _slot;
    if (slot == null) {
      _quote = null;
      return;
    }
    final quote = widget.api.quote(
      widget.offer.id,
      areaSqm: _perSqm ? _areaValue : null,
      startsAtIso: slot.startsAtIso,
      lat: _lat,
      lng: _lng,
      urgent: _urgent,
    );
    // The price block below the fold is built lazily; a refused quote (e.g. no point for a zoned venue) must not surface
    // as an unhandled error before anything listens. The FutureBuilder still receives the failure when it is built.
    quote.ignore();
    _quote = quote;
  }

  Future<void> _pickOnMap() async {
    final s = RideStrings(context);
    final owned = widget.maps == null;
    final maps = widget.maps ?? KundeMaps.forContext(context);
    try {
      final picked = await maps.pick(
        context,
        title:
            s.t('Адрес на карте', 'Картадағы мекенжай', 'Address on the map'),
        initial: _lat == null || _lng == null ? null : GeoPoint(_lat!, _lng!),
      );
      if (!mounted || picked == null) return;
      final name = picked.label(maps.config.language)?.trim();
      final text = name != null && name.isNotEmpty
          ? name
          : '${picked.point.lat.toStringAsFixed(5)}, ${picked.point.lon.toStringAsFixed(5)}';
      setState(() {
        _address.text = text;
        _pickedText = text;
        _lat = picked.point.lat;
        _lng = picked.point.lon;
        _error = null;
        _requote();
      });
    } finally {
      if (owned) maps.close();
    }
  }

  @override
  void dispose() {
    _address.dispose();
    _area.dispose();
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit(HomeServiceQuote quote) async {
    setState(() => _touched = true);
    final slot = _slot;
    if (slot == null || !_addressOk || (_perSqm && _areaValue == null)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final nav = Navigator.of(context);
    final s = RideStrings(context);
    try {
      final record = await widget.services.api.book(
        venueId: widget.offer.venueId,
        serviceId: widget.offer.serviceId,
        masterId: slot.masterId,
        startsAtIso: slot.startsAtIso,
        comment: _comment.text,
        addressText: _address.text,
        areaSqm: _perSqm ? _areaValue : null,
        idempotencyKey: _key,
        expectedPriceMinor: quote.totalMinor,
        urgent: _urgent,
        latitude: _lat,
        longitude: _lng,
      );
      if (!mounted) return;
      nav.popUntil((route) => route.isFirst);
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => BookingDetailScreen(
            services: widget.services,
            bookingId: record.id,
            initial: record,
            justBooked: true,
          ),
        ),
      );
    } on BookingException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = switch (e.failure) {
          BookingFailure.priceChanged => s.t(
              'Цена изменилась. Проверьте сумму и подтвердите снова.',
              'Баға өзгерді. Соманы тексеріп, қайта растаңыз.',
              'The price changed. Check the amount and confirm again.',
            ),
          BookingFailure.slotTaken => s.t(
              'Это время только что заняли. Выберите другое.',
              'Бұл уақытты жаңа ғана алды. Басқасын таңдаңыз.',
              'That time was just taken. Pick another.',
            ),
          BookingFailure.locationRequired => s.t(
              'Выберите адрес на карте: мастер работает по зонам обслуживания.',
              'Мекенжайды картадан таңдаңыз: шебер қызмет көрсету аймақтарында жұмыс істейді.',
              'Pick the address on the map: the master works in service zones.',
            ),
          BookingFailure.outOfZone => s.t(
              'Этот адрес вне зоны обслуживания мастера. Выберите другой адрес.',
              'Бұл мекенжай шебердің қызмет көрсету аймағынан тыс. Басқасын таңдаңыз.',
              'This address is outside the master\'s service zone. Pick another.',
            ),
          _ => s.error,
        };
        if (e.failure == BookingFailure.priceChanged) _requote();
        if (e.failure == BookingFailure.slotTaken) {
          _slot = null;
          _slots = _loadSlots();
          _quote = null;
        }
      });
    }
  }

  InputDecoration _plain(String hint, {String? error}) => InputDecoration(
        hintText: hint,
        errorText: error,
        isDense: true,
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: EdgeInsets.zero,
      );

  Widget _priceBlock(RideStrings s, ThemeData theme) =>
      FutureBuilder<HomeServiceQuote>(
        future: _quote,
        builder: (context, state) {
          if (_quote == null) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.t(
                    'Выберите время, чтобы увидеть цену',
                    'Бағаны көру үшін уақытты таңдаңыз',
                    'Pick a time to see the price',
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
              ],
            );
          }
          if (state.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.hasError) {
            final error = state.error;
            return Text(
              switch (error is BookingException ? error.failure : null) {
                BookingFailure.locationRequired => s.t(
                    'Выберите адрес на карте, чтобы увидеть цену',
                    'Бағаны көру үшін мекенжайды картадан таңдаңыз',
                    'Pick the address on the map to see the price',
                  ),
                BookingFailure.outOfZone => s.t(
                    'Этот адрес вне зоны обслуживания мастера',
                    'Бұл мекенжай шебердің қызмет көрсету аймағынан тыс',
                    'This address is outside the master\'s service zone',
                  ),
                _ => s.error,
              },
            );
          }
          final q = state.data!;
          Widget row(String label, int minor) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                    Text(formatKzt(minor)),
                  ],
                ),
              );
          return Column(
            children: [
              row(s.t('Услуга', 'Қызмет', 'Service'), q.listPriceMinor),
              if (q.callOutFeeMinor > 0)
                row(s.t('Выезд', 'Шығу', 'Call-out'), q.callOutFeeMinor),
              if (q.urgentSurchargeMinor > 0)
                row(
                  s.t('Срочность', 'Шұғылдық', 'Urgency'),
                  q.urgentSurchargeMinor,
                ),
              if (q.eveningSurchargeMinor > 0)
                row(
                  s.t('Вечернее время', 'Кешкі уақыт', 'Evening'),
                  q.eveningSurchargeMinor,
                ),
              const Divider(height: 28),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      s.t('Стоимость', 'Құны', 'Total'),
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  Text(
                    formatKzt(q.totalMinor),
                    style: theme.textTheme.headlineSmall,
                  ),
                ],
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton(
                key: const ValueKey('submit'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  shape: const StadiumBorder(),
                ),
                onPressed: _busy ? null : () => _submit(q),
                child: Text(
                  s.t(
                    'Заказать за ${formatKzt(q.totalMinor)}',
                    '${formatKzt(q.totalMinor)} тапсырыс беру',
                    'Order for ${formatKzt(q.totalMinor)}',
                  ),
                ),
              ),
            ],
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    final theme = Theme.of(context);
    final days = [for (var i = 0; i < 7; i++) _today.add(Duration(days: i))];
    const gap = SizedBox(height: 12);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          s.t('Оформление заказа', 'Тапсырысты рәсімдеу', 'Place order'),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              HomeServiceField(
                icon: homeCategoryMeta(s, widget.offer.categoryCode).$1,
                label: widget.offer.name(s.language),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.offer.venueName,
                      style:
                          TextStyle(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      priceLabel(s, widget.offer),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              gap,
              HomeServiceField(
                icon: Icons.calendar_month_rounded,
                label: s.t('Дата и время', 'Күні мен уақыты', 'Date and time'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 44,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final d in days)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                key: ValueKey('day-${d.month}-${d.day}'),
                                shape: const StadiumBorder(),
                                showCheckmark: false,
                                label: Text(
                                  '${d.day}.${d.month.toString().padLeft(2, '0')}',
                                ),
                                selected: d.day == _date.day &&
                                    d.month == _date.month,
                                onSelected: (_) => setState(() {
                                  _date = d;
                                  _slot = null;
                                  _quote = null;
                                  _slots = _loadSlots();
                                }),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    FutureBuilder<List<BookingSlot>>(
                      future: _slots,
                      builder: (context, state) {
                        if (state.connectionState != ConnectionState.done) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (state.hasError) return Text(s.error);
                        final slots = state.data!;
                        if (slots.isEmpty) {
                          return Text(
                            s.t(
                              'На эту дату нет свободного времени',
                              'Бұл күні бос уақыт жоқ',
                              'No free time on this date',
                            ),
                          );
                        }
                        // One entry per start time: the server picks the master by the slot it is given.
                        final seen = <String>{};
                        final unique = slots
                            .where((x) => seen.add(x.startsAtIso))
                            .toList();
                        return Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final slot in unique)
                              ChoiceChip(
                                key: ValueKey('slot-${slot.startsAtIso}'),
                                shape: const StadiumBorder(),
                                showCheckmark: false,
                                label: Text(
                                  '${slot.start.hour.toString().padLeft(2, '0')}:${slot.start.minute.toString().padLeft(2, '0')}',
                                ),
                                selected:
                                    _slot?.startsAtIso == slot.startsAtIso,
                                onSelected: (_) => setState(() {
                                  _slot = slot;
                                  _requote();
                                }),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              gap,
              HomeServiceField(
                icon: Icons.location_on_rounded,
                label: s.t('Адрес', 'Мекенжай', 'Address'),
                child: TextField(
                  key: const ValueKey('address'),
                  controller: _address,
                  decoration: _plain(
                    s.t(
                      'Улица, дом, квартира',
                      'Көше, үй, пәтер',
                      'Street, building, apartment',
                    ),
                    error: _touched && !_addressOk
                        ? s.t(
                            'Укажите адрес (от 5 символов)',
                            'Мекенжайды көрсетіңіз (кемінде 5 таңба)',
                            'Enter an address (5+ characters)',
                          )
                        : null,
                  ),
                  onChanged: (_) => setState(() {
                    if (_address.text != _pickedText) {
                      _lat = null;
                      _lng = null;
                    }
                  }),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('pick-on-map'),
                  onPressed: _pickOnMap,
                  icon: const Icon(Icons.map_outlined),
                  label: Text(
                    _lat == null
                        ? s.t(
                            'Выбрать на карте',
                            'Картадан таңдау',
                            'Pick on the map',
                          )
                        : s.t(
                            'Адрес выбран на карте',
                            'Мекенжай картадан таңдалды',
                            'Address picked on the map',
                          ),
                  ),
                ),
              ),
              if (_perSqm) ...[
                gap,
                HomeServiceField(
                  icon: Icons.square_foot_rounded,
                  label: s.t('Площадь, м²', 'Ауданы, м²', 'Area, m²'),
                  child: TextField(
                    key: const ValueKey('area'),
                    controller: _area,
                    keyboardType: TextInputType.number,
                    decoration: _plain(
                      '50',
                      error: _touched && _areaValue == null
                          ? s.t(
                              'Укажите площадь',
                              'Ауданын көрсетіңіз',
                              'Enter the area',
                            )
                          : null,
                    ),
                    onChanged: (_) => setState(_requote),
                  ),
                ),
              ],
              gap,
              HomeServiceField(
                icon: Icons.edit_outlined,
                label: s.t('Комментарий', 'Түсініктеме', 'Comment'),
                child: TextField(
                  controller: _comment,
                  maxLines: 2,
                  minLines: 1,
                  decoration: _plain(
                    s.t(
                      'Например: замена смесителя',
                      'Мысалы: араластырғышты ауыстыру',
                      'For example: replace a tap',
                    ),
                  ),
                ),
              ),
              SwitchListTile(
                key: const ValueKey('urgent'),
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                title: Text(s.t('Срочно', 'Шұғыл', 'Urgent')),
                value: _urgent,
                onChanged: (v) => setState(() {
                  _urgent = v;
                  _requote();
                }),
              ),
              const Divider(height: 28),
              _priceBlock(s, theme),
            ],
          ),
        ),
      ),
    );
  }
}
