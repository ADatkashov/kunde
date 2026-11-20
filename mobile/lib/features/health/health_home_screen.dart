import 'package:flutter/material.dart';

import '../booking/booking_services.dart';
import '../booking/data/booking_models.dart';
import '../booking/presentation/booking_strings.dart';
import '../booking/presentation/bookings_list.dart';
import '../booking/presentation/venue_screen.dart';
import '../food/presentation/food_widgets.dart';
import '../home/presentation/home_strings.dart';

class HealthHomeScreen extends StatefulWidget {
  const HealthHomeScreen({required this.services, super.key});

  final BookingServices services;

  @override
  State<HealthHomeScreen> createState() => _HealthHomeScreenState();
}

class _HealthHomeScreenState extends State<HealthHomeScreen> {
  static const _pageSize = 20;
  final _search = TextEditingController();
  String _direction = '';
  Map<String, String> _filters = const {};
  int _offset = 0;
  late Future<List<BookingVenue>> _venues = _load();

  Future<List<BookingVenue>> _load() => widget.services.api.healthVenues(
        query: _search.text.trim(),
        direction: _direction,
        limit: _pageSize,
        offset: _offset,
        filters: _filters,
      );

  void _refresh([int offset = 0]) => setState(() {
        _offset = offset;
        _venues = _load();
      });

  Future<void> _showFilters() async {
    final filters = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _HealthFiltersSheet(filters: _filters),
    );
    if (!mounted || filters == null) return;
    _filters = filters;
    _refresh();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = bkL10n(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final title = s.healthText(
      'Здоровье и благополучие',
      'Денсаулық және әл-ауқат',
      'Health & Wellness',
    );
    final history = s.healthText(
      'Мои записи',
      'Менің жазбаларым',
      'My appointments',
    );
    final directions = [
      (
        'DOCTORS',
        Icons.medical_services_outlined,
        s.healthText('Врачи', 'Дәрігерлер', 'Doctors'),
      ),
      (
        'CLINICS',
        Icons.local_hospital_outlined,
        s.healthText('Клиники', 'Клиникалар', 'Clinics'),
      ),
      (
        'DENTISTRY',
        Icons.health_and_safety_outlined,
        s.healthText('Стоматология', 'Стоматология', 'Dentistry'),
      ),
      (
        'DIAGNOSTICS',
        Icons.monitor_heart_outlined,
        s.healthText('Диагностика', 'Диагностика', 'Diagnostics'),
      ),
      (
        'LABS',
        Icons.science_outlined,
        s.healthText('Анализы', 'Талдаулар', 'Lab tests'),
      ),
      (
        'FITNESS',
        Icons.fitness_center_outlined,
        s.healthText('Фитнес', 'Фитнес', 'Fitness'),
      ),
      (
        'SPA',
        Icons.spa_outlined,
        s.healthText('SPA и массаж', 'SPA және массаж', 'Spa & massage'),
      ),
      (
        'WELLNESS',
        Icons.self_improvement,
        s.healthText('Другие услуги', 'Басқа қызметтер', 'Other services'),
      ),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(s.catHealth)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF251345),
                      Color(0xFF513291),
                      Color(0xFF6944AC),
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              s.healthText('Алматы', 'Алматы', 'Almaty'),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        title,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        s.healthText(
                          'Врачи, диагностика и wellness по записи',
                          'Дәрігерлер, диагностика және сауықтыру қызметтеріне жазылу',
                          'Appointments for clinics, diagnostics and wellness',
                        ),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                maxLength: 100,
                onSubmitted: (_) => _refresh(),
                decoration: InputDecoration(
                  counterText: '',
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                  hintText: s.healthText(
                    'Организация или услуга',
                    'Ұйым немесе қызмет',
                    'Organization or service',
                  ),
                  suffixIcon: IconButton(
                    tooltip: s.healthText('Найти', 'Іздеу', 'Search'),
                    onPressed: () => _refresh(),
                    icon: const Icon(Icons.search),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text(history),
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: Text(history)),
                        body: BookingsList(
                          services: widget.services,
                          healthOnly: true,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final (code, icon, label) in directions)
                    FilterChip(
                      avatar: Icon(icon, size: 20),
                      label: Text(label),
                      selected: _direction == code,
                      onSelected: (selected) {
                        _direction = selected ? code : '';
                        _refresh();
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.tune),
                  onPressed: _showFilters,
                  label: Text(s.healthText('Фильтры', 'Сүзгілер', 'Filters')),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                s.healthText('Организации', 'Ұйымдар', 'Organizations'),
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              FutureBuilder<List<BookingVenue>>(
                future: _venues,
                builder: (context, state) {
                  if (state.connectionState != ConnectionState.done) {
                    return const Column(
                      children: [
                        SkeletonBox(height: 72, radius: 16),
                        SizedBox(height: 8),
                        SkeletonBox(height: 72, radius: 16),
                      ],
                    );
                  }
                  if (state.hasError || state.data == null) {
                    return ListTile(
                      title: Text(
                        s.healthText(
                          'Каталог недоступен',
                          'Каталог қолжетімсіз',
                          'Catalog unavailable',
                        ),
                      ),
                      trailing: IconButton(
                        tooltip: s.bkRetry,
                        onPressed: () => _refresh(_offset),
                        icon: const Icon(Icons.refresh),
                      ),
                    );
                  }
                  final venues = state.data!;
                  return Column(
                    children: [
                      if (venues.isEmpty)
                        ListTile(
                          title: Text(
                            s.healthText(
                              'Ничего не найдено',
                              'Ештеңе табылмады',
                              'No results',
                            ),
                          ),
                        ),
                      for (final venue in venues)
                        Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          clipBehavior: Clip.antiAlias,
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: colors.primaryContainer,
                              foregroundColor: colors.onPrimaryContainer,
                              child: const Icon(Icons.place_outlined),
                            ),
                            title: Text(venue.name),
                            subtitle: Text(
                              [
                                venue.addressText,
                                if (venue.fromPriceMinor case final price?)
                                  formatTenge(price),
                              ].join(' · '),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.of(context).push<void>(
                              MaterialPageRoute(
                                builder: (_) => VenueScreen(
                                  services: widget.services,
                                  venue: venue,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (_offset > 0 || venues.length == _pageSize)
                        OverflowBar(
                          spacing: 8,
                          children: [
                            if (_offset > 0)
                              TextButton(
                                onPressed: () => _refresh(_offset - _pageSize),
                                child: Text(
                                  s.healthText('Назад', 'Артқа', 'Previous'),
                                ),
                              ),
                            if (venues.length == _pageSize)
                              TextButton(
                                onPressed: () => _refresh(_offset + _pageSize),
                                child: Text(
                                  s.healthText('Далее', 'Келесі', 'Next'),
                                ),
                              ),
                          ],
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HealthFiltersSheet extends StatefulWidget {
  const _HealthFiltersSheet({required this.filters});

  final Map<String, String> filters;

  @override
  State<_HealthFiltersSheet> createState() => _HealthFiltersSheetState();
}

class _HealthFiltersSheetState extends State<_HealthFiltersSheet> {
  static const _priceKeys = ['minPriceMinor', 'maxPriceMinor'];
  final _form = GlobalKey<FormState>();
  late final _fields = {
    for (final key in [
      'district',
      'organization',
      'service',
      'specialist',
      'specialty',
      ..._priceKeys,
    ])
      key: TextEditingController(
        text: _priceKeys.contains(key) && widget.filters.containsKey(key)
            ? (int.parse(widget.filters[key]!) ~/ 100).toString()
            : widget.filters[key],
      ),
  };

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _apply() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(context, {
      for (final entry in _fields.entries)
        if (entry.value.text.trim().isNotEmpty)
          entry.key: _priceKeys.contains(entry.key)
              ? (int.parse(entry.value.text.trim()) * 100).toString()
              : entry.value.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = bkL10n(context);
    final labels = {
      'district': s.healthText('Район', 'Аудан', 'District'),
      'organization': s.healthText('Организация', 'Ұйым', 'Organization'),
      'service': s.healthText('Услуга', 'Қызмет', 'Service'),
      'specialist': s.healthText('Специалист', 'Маман', 'Specialist'),
      'specialty': s.healthText('Специальность', 'Мамандық', 'Specialty'),
      'minPriceMinor': s.healthText(
        'Цена от, ₸',
        'Ең төменгі баға, ₸',
        'Min price, ₸',
      ),
      'maxPriceMinor': s.healthText(
        'Цена до, ₸',
        'Ең жоғары баға, ₸',
        'Max price, ₸',
      ),
    };
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          0,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                s.healthText('Фильтры', 'Сүзгілер', 'Filters'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              for (final entry in labels.entries)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: TextFormField(
                    controller: _fields[entry.key],
                    maxLength: _priceKeys.contains(entry.key) ? 12 : 100,
                    keyboardType: _priceKeys.contains(entry.key)
                        ? TextInputType.number
                        : TextInputType.text,
                    decoration: InputDecoration(
                      labelText: entry.value,
                      counterText: '',
                    ),
                    validator: (input) {
                      final value = input!.trim();
                      if (!_priceKeys.contains(entry.key) || value.isEmpty) {
                        return null;
                      }
                      if (!RegExp(r'^\d{1,12}$').hasMatch(value)) {
                        return s.healthText(
                          'Введите целую сумму в тенге',
                          'Теңгемен бүтін соманы енгізіңіз',
                          'Enter a whole amount in tenge',
                        );
                      }
                      final min = int.tryParse(
                        _fields['minPriceMinor']!.text.trim(),
                      );
                      if (entry.key == 'maxPriceMinor' &&
                          min != null &&
                          min > int.parse(value)) {
                        return s.healthText(
                          'Укажите сумму не ниже минимальной',
                          'Ең төменгі бағадан кем емес соманы енгізіңіз',
                          'Enter an amount at least as high as the minimum',
                        );
                      }
                      return null;
                    },
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _apply,
                child: Text(s.healthText('Применить', 'Қолдану', 'Apply')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, <String, String>{}),
                child: Text(s.healthText('Сбросить', 'Тазарту', 'Reset')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
