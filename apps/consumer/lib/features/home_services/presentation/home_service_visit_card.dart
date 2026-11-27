import 'dart:async';

import 'package:flutter/material.dart';

import 'package:kunde_ui/ride_strings.dart';

import 'home_services_widgets.dart';

/// Progress of a Home Services visit for the customer: the master is assigned, on the way (with an ETA), on site, or working.
/// Refreshes itself; a failed read keeps the last known state and never blocks the booking screen.
class HomeServiceVisitCard extends StatefulWidget {
  const HomeServiceVisitCard({
    required this.load,
    this.every = const Duration(seconds: 15),
    super.key,
  });

  final Future<Map<String, dynamic>> Function() load;
  final Duration every;

  @override
  State<HomeServiceVisitCard> createState() => _HomeServiceVisitCardState();
}

class _HomeServiceVisitCardState extends State<HomeServiceVisitCard> {
  Map<String, dynamic>? _visit;
  Timer? _timer;
  bool _inFlight = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(widget.every, (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// One read at a time: a slow answer is never overtaken and then overwritten by an older one.
  Future<void> _refresh() async {
    if (_inFlight) return;
    _inFlight = true;
    try {
      final visit = await widget.load();
      if (mounted) setState(() => _visit = visit);
    } catch (_) {
      // Keep the last known state.
    } finally {
      _inFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final visit = _visit;
    if (visit == null) return const SizedBox.shrink();
    final s = RideStrings(context);
    final status = '${visit['status']}';
    final stage = visit['stage'] as String?;
    final eta = visit['etaMinutes'] as int?;
    final (IconData icon, String text) = switch ((status, stage)) {
      ('IN_PROGRESS', _) => (
          Icons.handyman_outlined,
          s.t(
            'Мастер выполняет работу',
            'Шебер жұмыс істеп жатыр',
            'The master is working',
          ),
        ),
      ('CONFIRMED', 'ARRIVED') => (
          Icons.home_outlined,
          s.t('Мастер на месте', 'Шебер жетті', 'The master has arrived'),
        ),
      ('CONFIRMED', 'EN_ROUTE') => (
          Icons.directions_car_outlined,
          eta == null
              ? s.t('Мастер в пути', 'Шебер жолда', 'The master is on the way')
              : s.t(
                  'Мастер в пути, прибудет через ~$eta мин',
                  'Шебер жолда, ~$eta мин ішінде жетеді',
                  'The master is on the way, arriving in ~$eta min',
                ),
        ),
      ('CONFIRMED', _) => (
          Icons.schedule_outlined,
          s.t(
            'Мастер приедет в назначенное время',
            'Шебер белгіленген уақытта келеді',
            'The master will come at the scheduled time',
          ),
        ),
      _ => (Icons.info_outline, ''),
    };
    if (text.isEmpty) return const SizedBox.shrink();
    return Semantics(
      liveRegion: true,
      label: text,
      child: Card(
        key: const ValueKey('visit-card'),
        margin: const EdgeInsets.only(top: 12),
        elevation: 0,
        color: Theme.of(context)
            .colorScheme
            .primaryContainer
            .withValues(alpha: .35),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            children: [
              HomeServiceStepper(
                step: switch ((status, stage)) {
                  ('IN_PROGRESS', _) => 2,
                  ('CONFIRMED', 'ARRIVED' || 'EN_ROUTE') => 1,
                  _ => 0,
                },
                labels: [
                  s.t('Принят', 'Қабылданды', 'Accepted'),
                  s.t('В пути', 'Жолда', 'On the way'),
                  s.t('В работе', 'Жұмыста', 'Working'),
                  s.t('Завершён', 'Аяқталды', 'Done'),
                ],
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  icon,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: Text(
                  text,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
