import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:kunde_localization/kunde_localizations.dart';
import 'package:kunde_auth/auth_repository.dart';
import 'package:kunde_ui/beauty_ops_strings.dart';
import 'package:kunde_ui/beauty_strings.dart';
import 'package:kunde_ui/beauty_theme.dart';
import 'package:kunde_models/beauty_models.dart';
import 'package:kunde_api/beauty_ops_api.dart';
import 'package:kunde_ui/beauty_support.dart';
import 'package:kunde_ui/beauty_widgets.dart';

class _AdminData {
  const _AdminData(this.analytics, this.categories);

  final BeautyAnalytics analytics;
  final List<BeautyCategory> categories;
}

/// KUNDE Admin: «Красота и уход — Аналитика и управление» with KPI, bookings by day, category share and recent bookings.
class BeautyAdminScreen extends StatefulWidget {
  const BeautyAdminScreen({required this.auth, super.key});

  final AuthRepository auth;

  @override
  State<BeautyAdminScreen> createState() => _BeautyAdminScreenState();
}

class _BeautyAdminScreenState extends State<BeautyAdminScreen> {
  late final BeautyOpsApi _api = BeautyOpsApi(widget.auth);
  int _days = 7;
  late Future<_AdminData> _data = _load();

  Future<_AdminData> _load() async {
    final analytics = await _api.analytics(days: _days);
    final categories = await _api.categories();
    return _AdminData(analytics, categories);
  }

  void _setDays(int days) => setState(() {
        _days = days;
        _data = _load();
      });

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    return BeautyScope(
      child: Scaffold(
        appBar: AppBar(
            title: Text(s.boAdminTitle, style: const TextStyle(fontSize: 16))),
        body: FutureBuilder<_AdminData>(
          future: _data,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const BeautySkeleton();
            }
            if (snapshot.hasError) {
              return BeautyErrorView(
                  error: snapshot.error,
                  onRetry: () => setState(() {
                        _data = _load();
                      }));
            }
            return _AdminBody(
                data: snapshot.data!, days: _days, onDays: _setDays);
          },
        ),
      ),
    );
  }
}

class _AdminBody extends StatelessWidget {
  const _AdminBody(
      {required this.data, required this.days, required this.onDays});

  final _AdminData data;
  final int days;
  final ValueChanged<int> onDays;

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    final a = data.analytics;
    final names = {
      for (final c in data.categories) c.code: c.name(s.locale.languageCode)
    };
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            BeautyFilterChip(
                label: s.boPeriod7,
                selected: days == 7,
                onTap: () => onDays(7)),
            const SizedBox(width: 8),
            BeautyFilterChip(
                label: s.boPeriod30,
                selected: days == 30,
                onTap: () => onDays(30)),
          ],
        ),
        const SizedBox(height: 12),
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            mainAxisExtent: 120,
          ),
          children: [
            _Kpi(label: s.boSalons, value: '${a.salons}', delta: a.salonsDelta),
            _Kpi(
                label: s.boBookings,
                value: '${a.bookings}',
                delta: a.bookingsDelta),
            _Kpi(
                label: s.boRevenue,
                value: s.bMoney(a.revenueMinor),
                delta: a.revenueDelta),
            _Kpi(
                label: s.boAverageCheck,
                value: s.bMoney(a.averageCheckMinor),
                delta: a.averageDelta),
          ],
        ),
        BeautySectionHeader(s.boBookingsByDay),
        Container(
          height: 180,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: BeautyColors.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: CustomPaint(
            painter: _LinePainter(
                [for (final d in a.bookingsByDay) d.bookings.toDouble()]),
            size: Size.infinite,
          ),
        ),
        BeautySectionHeader(s.boCategories),
        if (a.categories.isEmpty)
          Text(s.boNoData, style: const TextStyle(color: BeautyColors.muted))
        else
          Row(
            children: [
              SizedBox(
                width: 130,
                height: 130,
                child: CustomPaint(
                  painter: _DonutPainter(
                      [for (final c in a.categories) c.bookings.toDouble()]),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: [
                    for (var i = 0; i < a.categories.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _palette[i % _palette.length],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                names[a.categories[i].code] ??
                                    a.categories[i].code,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text('${a.categories[i].percent}%',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        BeautySectionHeader(s.boRecent),
        if (a.recent.isEmpty)
          Text(s.boNoData, style: const TextStyle(color: BeautyColors.muted))
        else
          for (final r in a.recent)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${r.bookingNumber} · ${r.service}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        Text(
                            [r.client, r.salon]
                                .where((e) => e.isNotEmpty)
                                .join(' · '),
                            style: const TextStyle(color: BeautyColors.muted)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(s.bMoney(r.amountMinor),
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      BeautyBookingStatus(
                          status: r.status, label: s.boStatus(r.status)),
                    ],
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

const _palette = [
  Color(0xFF6C20F5),
  Color(0xFFB35CFF),
  Color(0xFF1FA463),
  Color(0xFFF2A81D),
  Color(0xFFE5484D),
  Color(0xFF2B8FF2),
  Color(0xFF8E8AA0),
  Color(0xFFFF7A59),
];

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value, this.delta});

  final String label;
  final String value;
  final int? delta;

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: BeautyColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BeautyColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label,
              style:
                  const TextStyle(fontSize: 12.5, color: BeautyColors.muted)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(value,
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          ),
          if (delta != null)
            Text(s.boDelta(delta!),
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: delta! >= 0
                        ? BeautyColors.success
                        : BeautyColors.error)),
        ],
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.values);

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final top = math.max(1.0, values.reduce(math.max));
    final dx = values.length == 1 ? 0.0 : size.width / (values.length - 1);
    final points = [
      for (var i = 0; i < values.length; i++)
        Offset(i * dx, size.height - (values[i] / top) * (size.height - 8) - 4)
    ];
    final fill = Path()..moveTo(points.first.dx, size.height);
    for (final p in points) {
      fill.lineTo(p.dx, p.dy);
    }
    fill
      ..lineTo(points.last.dx, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = const Color(0x226C20F5));
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      line.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
        line,
        Paint()
          ..color = BeautyColors.primary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5);
    for (final p in points) {
      canvas.drawCircle(p, 3.5, Paint()..color = BeautyColors.primary);
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.values != values;
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.values);

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (a, b) => a + b);
    if (total == 0) return;
    final rect = Offset.zero & size;
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * 2 * math.pi;
      canvas.drawArc(
          rect.deflate(14),
          start,
          sweep,
          false,
          Paint()
            ..color = _palette[i % _palette.length]
            ..style = PaintingStyle.stroke
            ..strokeWidth = 26);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.values != values;
}
