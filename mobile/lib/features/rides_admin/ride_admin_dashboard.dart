import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:kunde_auth/auth_repository.dart';
import 'package:kunde_ui/ride_strings.dart';

/// Figures from `admin/rides/summary` plus the latest rows of `admin/rides/trips`.
/// Money is the quoted tariff fare of completed, non-synthetic rides: no payment
/// is captured yet, so it is labelled as a fare total and never as paid revenue.
class RideAdminStats {
  RideAdminStats({
    required this.total,
    required this.active,
    required this.completed,
    required this.cancelled,
    required this.completedFare,
    required this.averageFare,
    required this.byClass,
    required this.perDay,
    required this.days,
    required this.recent,
  });

  factory RideAdminStats.fromJson(
    Map<String, dynamic> summary,
    List<Map<String, dynamic>> trips,
  ) {
    final perDay =
        (summary['perDay'] as List<dynamic>).cast<Map<String, dynamic>>();
    return RideAdminStats(
      total: (summary['total'] as num).toInt(),
      active: (summary['active'] as num).toInt(),
      completed: (summary['completed'] as num).toInt(),
      cancelled: (summary['cancelled'] as num).toInt(),
      completedFare: summary['completedFareKzt'] as num,
      averageFare: summary['averageFareKzt'] as num?,
      byClass: {
        for (final row in (summary['byClass'] as List<dynamic>)
            .cast<Map<String, dynamic>>())
          row['rideClass'] as String: (row['rides'] as num).toInt(),
      },
      perDay: [for (final row in perDay) (row['rides'] as num).toInt()],
      days: [for (final row in perDay) DateTime.parse(row['day'] as String)],
      recent: ([...trips]..sort((a, b) =>
              (b['createdAt'] as String).compareTo(a['createdAt'] as String)))
          .take(8)
          .toList(growable: false),
    );
  }

  final int total;
  final int active;
  final int completed;
  final int cancelled;
  final num completedFare;

  /// Null when no completed, non-synthetic ride exists.
  final num? averageFare;
  final Map<String, int> byClass;
  final List<int> perDay;
  final List<DateTime> days;
  final List<Map<String, dynamic>> recent;

  /// Rides that ended without a driver (for example no driver available).
  int get other => math.max(0, total - active - completed - cancelled);
}

class RideAdminDashboard extends StatefulWidget {
  const RideAdminDashboard({required this.auth, super.key});

  final AuthRepository auth;

  @override
  State<RideAdminDashboard> createState() => _RideAdminDashboardState();
}

class _RideAdminDashboardState extends State<RideAdminDashboard> {
  late Future<RideAdminStats> _stats = _load();

  Future<RideAdminStats> _load() async {
    final summary = await widget.auth
        .authorizedJson('GET', 'admin/rides/summary') as Map<String, dynamic>;
    final trips = await widget.auth.authorizedJson('GET', 'admin/rides/trips')
        as List<dynamic>;
    return RideAdminStats.fromJson(summary, trips.cast<Map<String, dynamic>>());
  }

  void _reload() => setState(() => _stats = _load());

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('Поездки — аналитика и управление',
            'Сапарлар — талдау және басқару', 'Rides — analytics')),
        actions: [
          IconButton(
            tooltip: s.t('Обновить', 'Жаңарту', 'Refresh'),
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<RideAdminStats>(
          future: _stats,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: TextButton(onPressed: _reload, child: Text(s.retry)),
              );
            }
            return _Body(stats: snapshot.requireData);
          },
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.stats});
  final RideAdminStats stats;

  static String _kzt(num value) {
    final digits = value.round().toString();
    final grouped = digits.replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '\u00A0');
    return '$grouped KZT';
  }

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    final scheme = Theme.of(context).colorScheme;
    const green = Color(0xFF22A06B);
    final kpis = [
      (
        s.t('Всего поездок', 'Барлық сапар', 'Total rides'),
        '${stats.total}',
        scheme.primary
      ),
      (
        s.t('Активные', 'Белсенді', 'Active'),
        '${stats.active}',
        scheme.tertiary
      ),
      (
        s.t('Сумма по тарифу', 'Тариф бойынша сома', 'Fare total'),
        _kzt(stats.completedFare),
        green
      ),
      (
        s.t('Средняя поездка', 'Орташа сапар', 'Average ride'),
        stats.averageFare == null ? '—' : _kzt(stats.averageFare!),
        scheme.onSurface
      ),
    ];
    final statuses = [
      (s.t('Завершены', 'Аяқталды', 'Completed'), stats.completed, green),
      (s.t('Активные', 'Белсенді', 'Active'), stats.active, scheme.primary),
      (
        s.t('Отменены', 'Тоқтатылды', 'Cancelled'),
        stats.cancelled,
        scheme.error
      ),
      (
        s.t('Без водителя', 'Жүргізушісіз', 'No driver'),
        stats.other,
        scheme.outline
      ),
    ];
    final classColors = [
      scheme.primary,
      scheme.tertiary,
      green,
      scheme.secondary,
    ];
    final classes = [
      for (final (index, entry) in stats.byClass.entries.indexed)
        (
          s.rideClass(entry.key),
          entry.value,
          classColors[index % classColors.length]
        ),
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final (label, value, color) in kpis)
              SizedBox(
                width: 190,
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label,
                            style: Theme.of(context).textTheme.labelLarge),
                        const SizedBox(height: 6),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            value,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: color,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          s.t(
            'Суммы считаются по тарифу для завершённых нетестовых поездок; оплата ещё не подключена.',
            'Сомалар аяқталған сынақ емес сапарлардың тарифі бойынша есептеледі; төлем әлі қосылмаған.',
            'Totals use the tariff fare of completed non-test rides; payment is not connected yet.',
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        _Panel(
          title: s.t('Поездки по дням (7 дней)',
              'Күндер бойынша сапарлар (7 күн)', 'Rides by day (7 days)'),
          child: SizedBox(
            height: 200,
            child: Semantics(
              label: s.t('График поездок за 7 дней', '7 күндегі сапар графигі',
                  'Rides over the last 7 days'),
              child: CustomPaint(
                painter: _DayChartPainter(
                  values: stats.perDay,
                  days: stats.days,
                  line: scheme.primary,
                  grid: scheme.outlineVariant,
                  text: scheme.onSurfaceVariant,
                ),
                size: Size.infinite,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _Panel(
          title: s.t('Типы поездок', 'Сапар түрлері', 'Ride classes'),
          child: _Split(
              items: classes,
              total: stats.total,
              empty: scheme.surfaceContainerHighest),
        ),
        const SizedBox(height: 16),
        _Panel(
          title: s.t('Статусы поездок', 'Сапар күйлері', 'Ride statuses'),
          child: _Split(
              items: statuses,
              total: stats.total,
              empty: scheme.surfaceContainerHighest),
        ),
        const SizedBox(height: 16),
        _Panel(
          title: s.t('Последние поездки', 'Соңғы сапарлар', 'Latest rides'),
          child: stats.recent.isEmpty
              ? Text(s.noRides)
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: [
                      DataColumn(
                          label: Text(s.t('№ заказа', 'Тапсырыс №', 'Ride'))),
                      DataColumn(label: Text(s.driverLabel)),
                      DataColumn(label: Text(s.tariffLabel)),
                      DataColumn(label: Text(s.fareLabel)),
                      DataColumn(label: Text(s.t('Дата', 'Күні', 'Date'))),
                      DataColumn(label: Text(s.t('Статус', 'Күйі', 'Status'))),
                    ],
                    rows: [
                      for (final trip in stats.recent)
                        DataRow(cells: [
                          DataCell(Text(_short(trip['id'] as String))),
                          DataCell(Text(trip['driverId'] == null
                              ? '—'
                              : _short(trip['driverId'] as String))),
                          DataCell(
                              Text(s.rideClass(trip['rideClass'] as String))),
                          DataCell(Text(_kzt(trip['fareKzt'] as num))),
                          DataCell(Text(MaterialLocalizations.of(context)
                              .formatShortDate(
                                  DateTime.parse(trip['createdAt'] as String)
                                      .toLocal()))),
                          DataCell(Text(s.status(trip['status'] as String))),
                        ]),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  static String _short(String id) =>
      'KND-${id.replaceAll('-', '').substring(0, 6).toUpperCase()}';
}

/// A donut with its legend and percentage shares.
class _Split extends StatelessWidget {
  const _Split({required this.items, required this.total, required this.empty});
  final List<(String, int, Color)> items;
  final int total;
  final Color empty;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          SizedBox.square(
            dimension: 130,
            child: CustomPaint(
              painter: _DonutPainter([
                for (final (_, value, color) in items) (value, color),
              ], empty),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              children: [
                for (final (label, value, color) in items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                              color: color, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(label)),
                        Text(
                          total == 0
                              ? '0%'
                              : '${(value * 100 / total).round()}%',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      );
}

class _DayChartPainter extends CustomPainter {
  const _DayChartPainter({
    required this.values,
    required this.days,
    required this.line,
    required this.grid,
    required this.text,
  });

  final List<int> values;
  final List<DateTime> days;
  final Color line;
  final Color grid;
  final Color text;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 28.0, bottom = 22.0, top = 8.0;
    final maxValue = math.max(values.fold<int>(0, math.max), 1);
    final width = size.width - left;
    final height = size.height - bottom - top;
    final label = TextStyle(color: text, fontSize: 11);
    for (var tick = 0; tick <= 2; tick++) {
      final value = (maxValue * tick / 2).round();
      final y = top + height * (1 - tick / 2);
      canvas.drawLine(
          Offset(left, y),
          Offset(size.width, y),
          Paint()
            ..color = grid
            ..strokeWidth = 1);
      _text(canvas, '$value', Offset(0, y - 7), label);
    }
    final points = [
      for (var i = 0; i < values.length; i++)
        Offset(left + width * i / (values.length - 1),
            top + height * (1 - values[i] / maxValue)),
    ];
    final area = Path()..moveTo(points.first.dx, top + height);
    for (final p in points) {
      area.lineTo(p.dx, p.dy);
    }
    area
      ..lineTo(points.last.dx, top + height)
      ..close();
    canvas.drawPath(area, Paint()..color = line.withValues(alpha: .12));
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );
    for (final p in points) {
      canvas.drawCircle(p, 3.5, Paint()..color = line);
    }
    for (var i = 0; i < days.length; i++) {
      _text(canvas, '${days[i].day}',
          Offset(points[i].dx - 5, size.height - 15), label);
    }
  }

  void _text(Canvas canvas, String value, Offset at, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_DayChartPainter old) =>
      old.values != values || old.line != line;
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter(this.segments, this.empty);
  final List<(int, Color)> segments;
  final Color empty;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = size.width * .2;
    final arc = rect.deflate(stroke / 2);
    final total = segments.fold<int>(0, (sum, s) => sum + s.$1);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    if (total == 0) {
      canvas.drawArc(arc, 0, 2 * math.pi, false, base..color = empty);
      return;
    }
    var start = -math.pi / 2;
    for (final (value, color) in segments) {
      if (value == 0) continue;
      final sweep = 2 * math.pi * value / total;
      canvas.drawArc(arc, start, sweep, false, base..color = color);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.segments != segments;
}
