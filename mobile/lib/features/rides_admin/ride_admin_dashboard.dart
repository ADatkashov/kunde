import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../identity/auth_repository.dart';
import '../rides/ride_strings.dart';

/// Aggregates computed from the real `admin/rides/trips` rows. The endpoint has
/// no fare, city or vehicle type, so revenue, average fare and type split are
/// not derived or invented here.
class RideAdminStats {
  RideAdminStats._({
    required this.total,
    required this.active,
    required this.completed,
    required this.cancelled,
    required this.other,
    required this.perDay,
    required this.days,
    required this.recent,
  });

  factory RideAdminStats.from(List<Map<String, dynamic>> trips, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final days = [
      for (var i = 6; i >= 0; i--) today.subtract(Duration(days: i)),
    ];
    final perDay = List<int>.filled(7, 0);
    var active = 0, completed = 0, cancelled = 0, other = 0;
    for (final trip in trips) {
      final status = trip['status'] as String;
      if (status == 'COMPLETED') {
        completed++;
      } else if (status.startsWith('CANCELLED')) {
        cancelled++;
      } else if (const {
        'REQUESTED',
        'SEARCHING_DRIVER',
        'DRIVER_ASSIGNED',
        'DRIVER_ARRIVING',
        'DRIVER_ARRIVED',
        'IN_PROGRESS',
      }.contains(status)) {
        active++;
      } else {
        other++;
      }
      final at = DateTime.parse(trip['createdAt'] as String).toLocal();
      final day = DateTime(at.year, at.month, at.day);
      final index = days.indexOf(day);
      if (index >= 0) perDay[index]++;
    }
    final recent = [...trips]..sort((a, b) =>
        (b['createdAt'] as String).compareTo(a['createdAt'] as String));
    return RideAdminStats._(
      total: trips.length,
      active: active,
      completed: completed,
      cancelled: cancelled,
      other: other,
      perDay: perDay,
      days: days,
      recent: recent.take(8).toList(growable: false),
    );
  }

  final int total;
  final int active;
  final int completed;
  final int cancelled;
  final int other;
  final List<int> perDay;
  final List<DateTime> days;
  final List<Map<String, dynamic>> recent;
}

class RideAdminDashboard extends StatefulWidget {
  const RideAdminDashboard(
      {required this.auth, this.now = DateTime.now, super.key});

  final AuthRepository auth;

  /// Clock for the 7-day window; tests pass a fixed one.
  final DateTime Function() now;

  @override
  State<RideAdminDashboard> createState() => _RideAdminDashboardState();
}

class _RideAdminDashboardState extends State<RideAdminDashboard> {
  late Future<RideAdminStats> _stats = _load();

  Future<RideAdminStats> _load() async {
    final rows = await widget.auth.authorizedJson('GET', 'admin/rides/trips')
        as List<dynamic>;
    return RideAdminStats.from(
      rows.cast<Map<String, dynamic>>(),
      widget.now(),
    );
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
                child: TextButton(
                  onPressed: _reload,
                  child: Text(s.retry),
                ),
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

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    final scheme = Theme.of(context).colorScheme;
    const green = Color(0xFF22A06B);
    final kpis = [
      (
        s.t('Всего поездок', 'Барлық сапар', 'Total rides'),
        stats.total,
        scheme.primary
      ),
      (s.t('Активные', 'Белсенді', 'Active'), stats.active, scheme.tertiary),
      (s.t('Завершены', 'Аяқталды', 'Completed'), stats.completed, green),
      (
        s.t('Отменены', 'Тоқтатылды', 'Cancelled'),
        stats.cancelled,
        scheme.error
      ),
    ];
    final segments = [
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final (label, value, color) in kpis)
              SizedBox(
                width: 170,
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
                        Text(
                          '$value',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: color,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
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
          title: s.t('Статусы поездок', 'Сапар күйлері', 'Ride statuses'),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 130,
                child: CustomPaint(
                  painter: _DonutPainter([
                    for (final (_, value, color) in segments) (value, color),
                  ], scheme.surfaceContainerHighest),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  children: [
                    for (final (label, value, color) in segments)
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
                              stats.total == 0
                                  ? '0%'
                                  : '${(value * 100 / stats.total).round()}%',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
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
