import 'package:flutter/material.dart';

import 'package:kunde_api/home_services_api.dart';
import 'package:kunde_ui/ride_strings.dart';

import '../../booking/booking_services.dart';
import 'home_service_order_screen.dart';

String formatKzt(int minor) {
  final tenge = (minor / 100).round().toString();
  final grouped =
      tenge.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ');
  return '$grouped ₸';
}

/// «Дом и быт»: published, moderated offers of approved partners.
class HomeServicesOffersScreen extends StatefulWidget {
  const HomeServicesOffersScreen({required this.services, this.api, super.key});

  final BookingServices services;

  /// Injected in tests; defaults to the booking transport.
  final HomeServicesCatalog? api;

  @override
  State<HomeServicesOffersScreen> createState() =>
      _HomeServicesOffersScreenState();
}

class _HomeServicesOffersScreenState extends State<HomeServicesOffersScreen> {
  static const _page = 20;

  late final HomeServicesCatalog _api =
      widget.api ?? HomeServicesApi(widget.services.api);
  final _items = <HomeServiceOffer>[];
  bool _loading = true;
  bool _failed = false;
  bool _more = false;

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  /// Loads the next page of the catalogue; earlier pages stay on screen, a failure keeps them and offers a retry.
  Future<void> _loadPage() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final page = await _api.offers(limit: _page, offset: _items.length);
      if (!mounted) return;
      setState(() {
        _items.addAll(page);
        _more = page.length == _page;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    Widget body;
    if (_items.isEmpty && _loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_items.isEmpty && _failed) {
      body = Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(s.error),
          TextButton(onPressed: _loadPage, child: Text(s.retry)),
        ]),
      );
    } else if (_items.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(s.t(
              'Пока нет доступных услуг в вашем городе',
              'Қазір қалаңызда қолжетімді қызметтер жоқ',
              'No services available yet')),
        ),
      );
    } else {
      body = ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _items.length + (_more || _failed || _loading ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          if (i == _items.length) {
            if (_loading) {
              return const Center(child: CircularProgressIndicator());
            }
            return Center(
              child: TextButton(
                key: const ValueKey('more'),
                onPressed: _loadPage,
                child: Text(_failed
                    ? s.retry
                    : s.t('Показать ещё', 'Тағы көрсету', 'Show more')),
              ),
            );
          }
          final offer = _items[i];
          return _OfferCard(
            offer: offer,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => HomeServiceOfferScreen(
                    offer: offer, services: widget.services, api: _api),
              ),
            ),
          );
        },
      );
    }
    return Scaffold(
      appBar: AppBar(
          title: Text(s.t('Дом и быт', 'Үй және тұрмыс', 'Home services'))),
      body: Center(
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640), child: body),
      ),
    );
  }
}

String priceLabel(RideStrings s, HomeServiceOffer o) => o.areaBased
    ? '${formatKzt(o.priceMinor)} + ${formatKzt(o.pricePerSqmMinor)} / ${s.t('м²', 'м²', 'm²')}'
    : switch (o.pricingModel) {
        'FROM' => '${s.t('от', 'бастап', 'from')} ${formatKzt(o.priceMinor)}',
        'HOURLY' => '${formatKzt(o.priceMinor)} / ${s.t('час', 'сағ', 'h')}',
        'PER_SQM' =>
          '${formatKzt(o.priceMinor)} + ${formatKzt(o.pricePerSqmMinor)} / ${s.t('м²', 'м²', 'm²')}',
        'QUOTE' => s.t('По расчёту', 'Есептеу бойынша', 'On quote'),
        'DIAGNOSTIC' =>
          '${s.t('диагностика', 'диагностика', 'diagnostics')} ${formatKzt(o.priceMinor)}',
        _ => formatKzt(o.priceMinor),
      };

class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.offer, required this.onTap});

  final HomeServiceOffer offer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    final theme = Theme.of(context);
    final title = offer.name(s.language);
    return Semantics(
      button: true,
      label: '$title, ${priceLabel(s, offer)}',
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: theme.colorScheme.outlineVariant)),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(offer.venueName,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  if (offer.homeVisit)
                    Chip(
                        label: Text(
                            s.t('Выезд на дом', 'Үйге шығу', 'Home visit'))),
                  if (offer.warrantyDays > 0)
                    Chip(
                        label: Text(
                            '${s.t('Гарантия', 'Кепілдік', 'Warranty')} ${offer.warrantyDays} ${s.t('дн.', 'күн', 'd')}')),
                ]),
                const SizedBox(height: 8),
                Text(priceLabel(s, offer),
                    style: theme.textTheme.titleLarge
                        ?.copyWith(color: theme.colorScheme.primary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One offer with an itemised server quote (area, urgency) and the way into booking.
class HomeServiceOfferScreen extends StatefulWidget {
  const HomeServiceOfferScreen(
      {required this.offer,
      required this.services,
      required this.api,
      super.key});

  final HomeServiceOffer offer;
  final BookingServices services;
  final HomeServicesCatalog api;

  @override
  State<HomeServiceOfferScreen> createState() => _HomeServiceOfferScreenState();
}

class _HomeServiceOfferScreenState extends State<HomeServiceOfferScreen> {
  final _area = TextEditingController();
  bool _urgent = false;
  Future<HomeServiceQuote>? _quote;

  @override
  void initState() {
    super.initState();
    _requote();
  }

  @override
  void dispose() {
    _area.dispose();
    super.dispose();
  }

  void _requote() {
    final area = int.tryParse(_area.text.trim());
    _quote = widget.api.quote(widget.offer.id,
        areaSqm: widget.offer.areaBased ? area : null, urgent: _urgent);
  }

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    final theme = Theme.of(context);
    final offer = widget.offer;
    return Scaffold(
      appBar: AppBar(title: Text(offer.name(s.language))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Text(offer.venueName, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
                '${s.t('Длительность', 'Ұзақтығы', 'Duration')}: ${offer.durationMinutes} ${s.t('мин', 'мин', 'min')}'),
            if (offer.warrantyDays > 0)
              Text(
                  '${s.t('Гарантия', 'Кепілдік', 'Warranty')}: ${offer.warrantyDays} ${s.t('дн.', 'күн', 'd')}'),
            const SizedBox(height: 16),
            if (offer.areaBased)
              TextField(
                key: const ValueKey('area'),
                controller: _area,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                    labelText: s.t('Площадь, м²', 'Ауданы, м²', 'Area, m²')),
                onChanged: (_) => setState(_requote),
              ),
            SwitchListTile(
              key: const ValueKey('urgent'),
              contentPadding: EdgeInsets.zero,
              title: Text(s.t('Срочно', 'Шұғыл', 'Urgent')),
              value: _urgent,
              onChanged: (v) => setState(() {
                _urgent = v;
                _requote();
              }),
            ),
            const SizedBox(height: 8),
            FutureBuilder<HomeServiceQuote>(
              future: _quote,
              builder: (context, state) {
                if (state.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state.hasError) {
                  return Text(s.error);
                }
                final q = state.data!;
                Widget row(String label, int minor, {bool bold = false}) =>
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(children: [
                        Expanded(
                            child: Text(label,
                                style:
                                    bold ? theme.textTheme.titleMedium : null)),
                        Text(formatKzt(minor),
                            style: bold ? theme.textTheme.titleMedium : null),
                      ]),
                    );
                return Column(children: [
                  row(s.t('Услуга', 'Қызмет', 'Service'), q.listPriceMinor),
                  if (q.callOutFeeMinor > 0)
                    row(s.t('Выезд', 'Шығу', 'Call-out'), q.callOutFeeMinor),
                  if (q.urgentSurchargeMinor > 0)
                    row(s.t('Срочность', 'Шұғылдық', 'Urgency'),
                        q.urgentSurchargeMinor),
                  if (q.eveningSurchargeMinor > 0)
                    row(s.t('Вечернее время', 'Кешкі уақыт', 'Evening'),
                        q.eveningSurchargeMinor),
                  const Divider(),
                  row(s.t('Итого', 'Барлығы', 'Total'), q.totalMinor,
                      bold: true),
                ]);
              },
            ),
            const SizedBox(height: 24),
            FilledButton(
              key: const ValueKey('order'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => HomeServiceOrderScreen(
                        offer: offer,
                        services: widget.services,
                        api: widget.api,
                        initialAreaSqm: int.tryParse(_area.text.trim()),
                        initialUrgent: _urgent)),
              ),
              child: Text(s.t('Заказать услугу', 'Қызметке тапсырыс беру',
                  'Order the service')),
            ),
          ]),
        ),
      ),
    );
  }
}
