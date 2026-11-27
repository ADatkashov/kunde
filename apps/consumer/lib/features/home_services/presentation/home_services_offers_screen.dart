import 'package:flutter/material.dart';

import 'package:kunde_api/home_services_api.dart';
import 'package:kunde_ui/ride_strings.dart';

import '../../booking/booking_services.dart';
import 'home_service_order_screen.dart';
import 'home_services_widgets.dart';

String formatKzt(int minor) {
  final tenge = (minor / 100).round().toString();
  final grouped = tenge.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ' ',
  );
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
  String? _category;
  String _term = '';

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

  List<HomeServiceOffer> _visible(RideStrings s) {
    final term = _term.trim().toLowerCase();
    return [
      for (final o in _items)
        if ((_category == null || o.categoryCode == _category) &&
            (term.isEmpty ||
                o.name(s.language).toLowerCase().contains(term) ||
                o.venueName.toLowerCase().contains(term)))
          o,
    ];
  }

  Widget _filters(RideStrings s) {
    final codes = <String>[];
    for (final o in _items) {
      if (!codes.contains(o.categoryCode)) codes.add(o.categoryCode);
    }
    if (codes.length < 2) return const SizedBox.shrink();
    Widget chip(String? code, String label, IconData? icon) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            key: ValueKey('category-${code ?? 'all'}'),
            avatar: icon == null ? null : Icon(icon, size: 18),
            label: Text(label),
            selected: _category == code,
            showCheckmark: false,
            shape: const StadiumBorder(),
            onSelected: (_) => setState(() => _category = code),
          ),
        );
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          chip(null, s.t('Все', 'Барлығы', 'All'), null),
          for (final code in codes)
            chip(
              code,
              homeCategoryMeta(s, code).$2,
              homeCategoryMeta(s, code).$1,
            ),
        ],
      ),
    );
  }

  Widget _search(RideStrings s) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: SearchBar(
          key: const ValueKey('search'),
          hintText: s.t(
            'Найти услугу или специалиста',
            'Қызмет немесе маман іздеу',
            'Find a service or a pro',
          ),
          leading: const Icon(Icons.search_rounded),
          elevation: const WidgetStatePropertyAll(0),
          onChanged: (v) => setState(() => _term = v),
        ),
      );

  Widget _list(RideStrings s) {
    if (_items.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty && _failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(s.error),
            TextButton(onPressed: _loadPage, child: Text(s.retry)),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            s.t(
              'Пока нет доступных услуг в вашем городе',
              'Қазір қалаңызда қолжетімді қызметтер жоқ',
              'No services available yet',
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final visible = _visible(s);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: visible.length + 1 + (_more || _failed || _loading ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${s.t('Найдено', 'Табылды', 'Found')}: ${visible.length}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          );
        }
        if (i == visible.length + 1) {
          if (_loading) {
            return const Center(child: CircularProgressIndicator());
          }
          return Center(
            child: TextButton(
              key: const ValueKey('more'),
              onPressed: _loadPage,
              child: Text(
                _failed
                    ? s.retry
                    : s.t('Показать ещё', 'Тағы көрсету', 'Show more'),
              ),
            ),
          );
        }
        final offer = visible[i - 1];
        return _OfferCard(
          offer: offer,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => HomeServiceOfferScreen(
                offer: offer,
                services: widget.services,
                api: _api,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            children: [
              HomeServicesHero(
                title: s.t('Дом и быт', 'Үй және тұрмыс', 'Home services'),
                subtitle: s.t(
                  'Надёжные мастера и услуги для вашего дома',
                  'Үйіңізге сенімді шеберлер мен қызметтер',
                  'Trusted pros and services for your home',
                ),
              ),
              Expanded(
                child: HomeServicesSheet(
                  child: Column(
                    children: [
                      _search(s),
                      _filters(s),
                      Expanded(child: _list(s)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
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
    final icon = homeCategoryMeta(s, offer.categoryCode).$1;
    return Semantics(
      button: true,
      label: '$title, ${priceLabel(s, offer)}',
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: .6),
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HomeServiceTile(icon, size: 84),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        offer.venueName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          HomeServicePill(priceLabel(s, offer), strong: true),
                          if (offer.warrantyDays > 0)
                            HomeServicePill(
                              '${s.t('Гарантия', 'Кепілдік', 'Warranty')} ${offer.warrantyDays} ${s.t('дн.', 'күн', 'd')}',
                              icon: Icons.verified_user_outlined,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.colorScheme.outline,
                ),
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
  const HomeServiceOfferScreen({
    required this.offer,
    required this.services,
    required this.api,
    super.key,
  });

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
    _quote = widget.api.quote(
      widget.offer.id,
      areaSqm: widget.offer.areaBased ? area : null,
      urgent: _urgent,
    );
  }

  Widget _feature(IconData icon, String title, String caption) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withValues(alpha: .35),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    caption,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quoteBlock(RideStrings s) {
    final theme = Theme.of(context);
    return FutureBuilder<HomeServiceQuote>(
      future: _quote,
      builder: (context, state) {
        if (state.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.hasError) {
          return Text(s.error);
        }
        final q = state.data!;
        Widget row(String label, int minor, {bool bold = false}) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: bold ? theme.textTheme.titleMedium : null,
                    ),
                  ),
                  Text(
                    formatKzt(minor),
                    style: bold
                        ? theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          )
                        : null,
                  ),
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
            const Divider(height: 20),
            row(s.t('Итого', 'Барлығы', 'Total'), q.totalMinor, bold: true),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    final theme = Theme.of(context);
    final offer = widget.offer;
    final (icon, category) = homeCategoryMeta(s, offer.categoryCode);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: 240,
                child: ExcludeSemantics(
                  child: Image.asset(
                    'assets/photos/home-services.jpg',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              Positioned(
                top: 0,
                left: 4,
                child: SafeArea(
                  child: IconButton.filledTonal(
                    tooltip:
                        MaterialLocalizations.of(context).backButtonTooltip,
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 18,
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                top: 200,
                child: Material(
                  color: theme.scaffoldBackgroundColor,
                  elevation: 0,
                  shadowColor: Colors.transparent,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
                          children: [
                            Text(
                              offer.name(s.language),
                              style: theme.textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              offer.venueName,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                HomeServicePill(category, icon: icon),
                                if (offer.homeVisit)
                                  HomeServicePill(
                                    s.t(
                                      'Выезд на дом',
                                      'Үйге шығу',
                                      'Home visit',
                                    ),
                                    icon: Icons.home_outlined,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Text(
                              priceLabel(s, offer),
                              style: theme.textTheme.headlineSmall?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                _feature(
                                  Icons.schedule_rounded,
                                  s.t('Длительность', 'Ұзақтығы', 'Duration'),
                                  '${offer.durationMinutes} ${s.t('мин', 'мин', 'min')}',
                                ),
                                if (offer.warrantyDays > 0) ...[
                                  const SizedBox(width: 10),
                                  _feature(
                                    Icons.verified_user_outlined,
                                    s.t('Гарантия', 'Кепілдік', 'Warranty'),
                                    '${offer.warrantyDays} ${s.t('дн.', 'күн', 'd')}',
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 18),
                            if (offer.areaBased)
                              TextField(
                                key: const ValueKey('area'),
                                controller: _area,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: s.t(
                                    'Площадь, м²',
                                    'Ауданы, м²',
                                    'Area, m²',
                                  ),
                                ),
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
                            _quoteBlock(s),
                          ],
                        ),
                      ),
                      SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                          child: FilledButton(
                            key: const ValueKey('order'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(56),
                              shape: const StadiumBorder(),
                            ),
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => HomeServiceOrderScreen(
                                  offer: offer,
                                  services: widget.services,
                                  api: widget.api,
                                  initialAreaSqm: int.tryParse(
                                    _area.text.trim(),
                                  ),
                                  initialUrgent: _urgent,
                                ),
                              ),
                            ),
                            child: Text(
                              s.t(
                                'Заказать услугу',
                                'Қызметке тапсырыс беру',
                                'Order the service',
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
