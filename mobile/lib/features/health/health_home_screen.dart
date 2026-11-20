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
  int _offset = 0;
  late Future<List<BookingVenue>> _venues = _load();

  Future<List<BookingVenue>> _load() => widget.services.api.healthVenues(
        query: _search.text.trim(),
        direction: _direction,
        limit: _pageSize,
        offset: _offset,
      );

  void _refresh([int offset = 0]) => setState(() {
        _offset = offset;
        _venues = _load();
      });

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
