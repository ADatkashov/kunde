import 'package:flutter/material.dart';

import 'package:kunde_auth/auth_repository.dart';
import 'package:kunde_ui/ride_strings.dart';

class HealthAdminScreen extends StatefulWidget {
  const HealthAdminScreen({required this.auth, super.key});

  final AuthRepository auth;

  @override
  State<HealthAdminScreen> createState() => _HealthAdminScreenState();
}

class _HealthAdminScreenState extends State<HealthAdminScreen> {
  late Future<Map<String, dynamic>> _overview = _load();
  bool _saving = false;

  Future<Map<String, dynamic>> _load() async =>
      await widget.auth.authorizedJson('GET', 'admin/health')
          as Map<String, dynamic>;

  void _refresh() => setState(() => _overview = _load());

  Future<void> _publish(String id, bool published) async {
    setState(() => _saving = true);
    try {
      await widget.auth.authorizedJson(
        'PATCH',
        'admin/health/venues/$id',
        body: {'published': published},
        expected: const {204},
      );
      if (mounted) _refresh();
    } catch (_) {
      if (!mounted) return;
      final s = RideStrings(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            s.t(
              'Изменение не сохранено',
              'Өзгеріс сақталмады',
              'Could not save the change',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          s.t(
            'Здоровье и благополучие',
            'Денсаулық және әл-ауқат',
            'Health & Wellness',
          ),
        ),
        actions: [
          IconButton(
            tooltip: s.t('Обновить', 'Жаңарту', 'Refresh'),
            onPressed: _saving ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: FutureBuilder<Map<String, dynamic>>(
            future: _overview,
            builder: (context, state) {
              if (state.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (state.hasError || state.data == null) {
                return Center(
                  child: FilledButton.tonalIcon(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh),
                    label: Text(
                      s.t(
                        'Повторить загрузку',
                        'Қайта жүктеу',
                        'Retry loading',
                      ),
                    ),
                  ),
                );
              }
              final data = state.data!;
              final venues = (data['venues'] as List<dynamic>)
                  .cast<Map<String, dynamic>>();
              final counts = (data['appointmentCounts'] as List<dynamic>)
                  .cast<Map<String, dynamic>>();
              String status(Object? code) => switch (code) {
                    'PENDING' => s.t('Ожидают', 'Күтуде', 'Pending'),
                    'CONFIRMED' => s.t('Подтверждены', 'Расталды', 'Confirmed'),
                    'COMPLETED' => s.t('Завершены', 'Аяқталды', 'Completed'),
                    'CANCELLED' => s.t('Отменены', 'Бас тартылды', 'Cancelled'),
                    _ => code.toString(),
                  };
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    s.t('Записи', 'Жазбалар', 'Appointments'),
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      for (final row in counts)
                        Chip(
                          label: Text(
                            '${status(row['status'])} · ${row['total']}',
                          ),
                        ),
                      if (counts.isEmpty)
                        Text(
                          s.t(
                            'Записей пока нет',
                            'Жазбалар әзірге жоқ',
                            'No appointments yet',
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    s.t('Демо-каталог', 'Демо каталог', 'Demo catalog'),
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  if (venues.isEmpty)
                    Text(
                      s.t('Каталог пуст', 'Каталог бос', 'Catalog is empty'),
                    ),
                  for (final venue in venues)
                    Card(
                      child: SwitchListTile(
                        title: Text(venue['name'] as String),
                        subtitle: Text(
                          s.t(
                            'Показывать в каталоге',
                            'Каталогта көрсету',
                            'Show in catalog',
                          ),
                        ),
                        value: venue['published'] == true,
                        onChanged: _saving
                            ? null
                            : (value) => _publish(venue['id'] as String, value),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
