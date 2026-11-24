import 'package:flutter/material.dart';

import 'package:kunde_ui/ride_strings.dart';
import 'package:kunde_ui/ride_widgets.dart' show rideFare;
import 'executor_api.dart';

/// Real figures for the driver's home card. Nothing here is estimated beyond
/// the quoted tariff fare, and test-route rides never count as income.
class ExecutorDaySummary {
  const ExecutorDaySummary(
      {required this.todayTrips,
      required this.todayFare,
      required this.weekFare,
      required this.completed,
      required this.cancelled});

  factory ExecutorDaySummary.of(List<ExecutorTrip> trips, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final week = today.subtract(const Duration(days: 6));
    var todayTrips = 0;
    num todayFare = 0, weekFare = 0;
    var completed = 0, cancelled = 0;
    for (final trip in trips) {
      if (trip.status == 'COMPLETED') {
        completed++;
        final at = (trip.completedAt ?? trip.createdAt).toLocal();
        final day = DateTime(at.year, at.month, at.day);
        final fare = trip.synthetic ? 0 : (trip.fareKzt ?? 0);
        if (day == today) {
          todayTrips++;
          todayFare += fare;
        }
        if (!day.isBefore(week)) weekFare += fare;
      } else if (trip.status.startsWith('CANCELLED')) {
        cancelled++;
      }
    }
    return ExecutorDaySummary(
        todayTrips: todayTrips,
        todayFare: todayFare,
        weekFare: weekFare,
        completed: completed,
        cancelled: cancelled);
  }

  final int todayTrips;
  final num todayFare;
  final num weekFare;
  final int completed;
  final int cancelled;
}

const _violet = Color(0xFF7055F5);
const _violetDeep = Color(0xFF5136B4);
const _green = Color(0xFF1DB954);

/// "On line" banner with the availability switch, as in the reference.
class ExecutorOnlineBanner extends StatelessWidget {
  const ExecutorOnlineBanner(
      {required this.online,
      required this.onChanged,
      required this.hint,
      super.key});

  final bool online;
  final ValueChanged<bool>? onChanged;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = online ? _green : Theme.of(context).disabledColor;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(
        color: online
            ? _green.withValues(alpha: dark ? .22 : .12)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        ExcludeSemantics(
            child: Icon(Icons.verified_user_rounded, color: accent, size: 22)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.t('На линии', 'Желіде', 'Online'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: online ? _green : null)),
              Text(hint, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        Switch(
          value: online,
          onChanged: onChanged,
          activeThumbColor: Colors.white,
          activeTrackColor: _green,
        ),
      ]),
    );
  }
}

/// Today's income, completed rides and rating.
class ExecutorEarningsCard extends StatelessWidget {
  const ExecutorEarningsCard(
      {required this.summary, required this.rating, super.key});

  final ExecutorDaySummary summary;
  final num? rating;

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s.t('Сегодня', 'Бүгін', 'Today'),
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(rideFare(summary.todayFare),
            key: const Key('executor-today-fare'),
            style: text.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            Expanded(
                child: _Stat(
                    label: s.t('Поездки', 'Сапарлар', 'Rides'),
                    value: '${summary.todayTrips}',
                    valueKey: const Key('executor-today-trips'))),
            const SizedBox(height: 32, child: VerticalDivider()),
            Expanded(
                child: _Stat(
                    label: s.t('Рейтинг', 'Рейтинг', 'Rating'),
                    value: rating == null
                        ? '—'
                        : rating!.toStringAsFixed(rating! % 1 == 0 ? 0 : 2),
                    valueKey: const Key('executor-rating'),
                    end: true)),
          ]),
        ),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(
      {required this.label,
      required this.value,
      required this.valueKey,
      this.end = false});
  final String label;
  final String value;
  final Key valueKey;
  final bool end;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment:
          end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(label, style: text.bodySmall),
        Text(value,
            key: valueKey,
            style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
      ],
    );
  }
}

/// The wide violet call to action under the earnings card.
class ExecutorPrimaryButton extends StatelessWidget {
  const ExecutorPrimaryButton(
      {required this.label, required this.onPressed, super.key});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: ExcludeSemantics(
        child: Opacity(
          opacity: enabled ? 1 : .5,
          child: Material(
            color: Colors.transparent,
            child: Ink(
              height: 56,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [_violet, _violetDeep],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight),
                borderRadius: BorderRadius.circular(18),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: onPressed,
                child: Center(
                    child: Text(label,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800))),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One row of the driver menu: a lilac icon tile, a title and a chevron.
class ExecutorMenuTile extends StatelessWidget {
  const ExecutorMenuTile(
      {required this.icon,
      required this.title,
      required this.onTap,
      super.key});

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _violet.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ExcludeSemantics(child: Icon(icon, color: _violet, size: 22)),
        ),
        title: Text(title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      );
}
