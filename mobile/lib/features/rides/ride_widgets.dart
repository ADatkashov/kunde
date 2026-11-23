import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:kunde_design/kunde_design.dart';

import 'ride_api.dart';
import 'ride_strings.dart';

/// A server fare as the reference shows it: `1 200 ₸`. Whole tenge have no
/// decimals; a fractional estimate keeps two so nothing is rounded silently.
String rideFare(num value) {
  final cents = (value * 100).round();
  final fraction = cents % 100;
  final digits = (cents ~/ 100).toString();
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write('\u00A0');
    grouped.write(digits[i]);
  }
  final decimals =
      fraction == 0 ? '' : '.${fraction.toString().padLeft(2, '0')}';
  return '$grouped$decimals\u00A0₸';
}

/// One selectable fare class. [price] is shown only after the server has issued
/// a quote for this class; nothing is estimated on the device.
class RideTariffCard extends StatelessWidget {
  const RideTariffCard({
    required this.value,
    required this.selected,
    required this.onTap,
    this.price,
    super.key,
  });

  final String value;
  final bool selected;
  final String? price;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: .10)
            : scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  Icons.directions_car_filled_rounded,
                  size: 32,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.rideClass(value),
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        s.tariffHint(value),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (price != null)
                  Text(
                    price!,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen "finding a driver" state. It reflects the real server status:
/// the first step is active until dispatch starts, the second while drivers are
/// being matched. Assignment is never simulated by a timer.
class RideSearchingView extends StatefulWidget {
  const RideSearchingView({required this.requested, this.footer, super.key});

  /// True while the ride is only REQUESTED, false once SEARCHING_DRIVER.
  final bool requested;
  final Widget? footer;

  @override
  State<RideSearchingView> createState() => _RideSearchingViewState();
}

class _RideSearchingViewState extends State<RideSearchingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _radar = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _radar.stop();
    } else if (!_radar.isAnimating) {
      _radar.repeat();
    }
  }

  @override
  void dispose() {
    _radar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    const white = Colors.white;
    final steps = [
      (s.stepSend, widget.requested ? _Step.active : _Step.done),
      (s.stepMatch, widget.requested ? _Step.pending : _Step.active),
      (s.stepConfirm, _Step.pending),
    ];
    return ColoredBox(
      color: KundePalette.darkBackground,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: ExcludeSemantics(
                    child: SizedBox.square(
                      dimension: 240,
                      child: AnimatedBuilder(
                        animation: _radar,
                        builder: (_, __) => CustomPaint(
                          painter: _RadarPainter(_radar.value),
                          child: const Center(
                            child: Icon(
                              Icons.local_taxi_rounded,
                              size: 44,
                              color: white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Semantics(
                liveRegion: true,
                child: Text(
                  s.searchingTitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: white,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                s.searchingHint,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.white70),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    for (final (label, state) in steps)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            switch (state) {
                              _Step.done => const Icon(
                                  Icons.check_circle_rounded,
                                  color: KundePalette.brand,
                                ),
                              _Step.active => const SizedBox.square(
                                  dimension: 24,
                                  child: Padding(
                                    padding: EdgeInsets.all(2),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                    ),
                                  ),
                                ),
                              _Step.pending => const Icon(
                                  Icons.radio_button_unchecked_rounded,
                                  color: Colors.black38,
                                ),
                            },
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                label,
                                style: const TextStyle(
                                  color: KundePalette.ink,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (widget.footer != null) ...[
                const SizedBox(height: 16),
                widget.footer!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

enum _Step { done, active, pending }

class _RadarPainter extends CustomPainter {
  const _RadarPainter(this.progress);
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    canvas.drawCircle(
      center,
      radius * .28,
      Paint()..color = KundePalette.brand,
    );
    for (var ring = 0; ring < 3; ring++) {
      final t = (progress + ring / 3) % 1;
      canvas.drawCircle(
        center,
        radius * (.28 + .72 * t),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = KundePalette.brand.withValues(alpha: .55 * (1 - t)),
      );
    }
    canvas.drawCircle(
      center,
      radius * .28 + 6 * math.sin(progress * 2 * math.pi).abs(),
      Paint()..color = KundePalette.brand.withValues(alpha: .25),
    );
  }

  @override
  bool shouldRepaint(_RadarPainter old) => old.progress != progress;
}

/// Driver, vehicle and plate exactly as the server returned them. Rating and
/// contact are not shown: the backend does not expose them yet.
class RideDriverCard extends StatelessWidget {
  const RideDriverCard({required this.driver, this.status, super.key});

  final AssignedRideDriver driver;
  final String? status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: scheme.primary.withValues(alpha: .12),
              child: Text(
                driver.name.isEmpty ? '?' : driver.name.characters.first,
                style:
                    theme.textTheme.titleLarge?.copyWith(color: scheme.primary),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    driver.name,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  if (driver.vehicleSummary case final summary?)
                    Text(summary, style: theme.textTheme.bodyMedium),
                  if (driver.rating case final rating?)
                    Text(
                      '★ ${rating.toStringAsFixed(1)} (${driver.ratings})',
                      style: theme.textTheme.labelLarge,
                    ),
                  if (status != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          status!,
                          style: theme.textTheme.labelLarge
                              ?.copyWith(color: scheme.primary),
                        ),
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
}

/// The "ride complete" state. The fare is the server's estimate for the trip;
/// payment is not claimed until its backend exists. The customer can rate the
/// driver once: [onRate] stores the rating, and a rating already on the server
/// is shown read-only.
class RideCompletedView extends StatefulWidget {
  const RideCompletedView({
    required this.trip,
    required this.onDone,
    this.onRate,
    super.key,
  });

  final RideTrip trip;
  final VoidCallback onDone;
  final Future<void> Function(int stars, String? comment)? onRate;

  @override
  State<RideCompletedView> createState() => _RideCompletedViewState();
}

class _RideCompletedViewState extends State<RideCompletedView> {
  final _comment = TextEditingController();
  int _stars = 0;
  bool _saving = false;
  bool _failed = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _done() async {
    final rate = widget.onRate;
    if (_stars == 0 || rate == null) {
      widget.onDone();
      return;
    }
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      await rate(_stars, _comment.text);
      if (mounted) widget.onDone();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    final theme = Theme.of(context);
    final trip = widget.trip;
    final rated = trip.myRating;
    final date = MaterialLocalizations.of(context)
        .formatMediumDate(trip.createdAt.toLocal());
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 24),
        Center(
          child: Container(
            width: 84,
            height: 84,
            decoration: const BoxDecoration(
              color: Color(0xFF22A06B),
              shape: BoxShape.circle,
            ),
            child:
                const Icon(Icons.check_rounded, color: Colors.white, size: 52),
          ),
        ),
        const SizedBox(height: 20),
        Semantics(
          liveRegion: true,
          child: Text(
            s.completedTitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${trip.fare} KZT',
          textAlign: TextAlign.center,
          style: theme.textTheme.displaySmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _Row(label: s.tripDate, value: date),
                if (trip.driver case final driver?) ...[
                  const Divider(height: 24),
                  _Row(label: s.driverLabel, value: driver.name),
                  if (driver.vehicleSummary case final summary?)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _Row(label: '', value: summary),
                    ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        if (rated != null) ...[
          _Stars(value: rated, onChanged: null),
          const SizedBox(height: 4),
          Text(
            s.thanksRated,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ] else if (widget.onRate != null) ...[
          _Stars(
            value: _stars,
            onChanged: _saving ? null : (n) => setState(() => _stars = n),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _comment,
            enabled: !_saving,
            maxLength: 500,
            maxLines: 2,
            decoration: InputDecoration(hintText: s.rateHint),
          ),
          if (_failed)
            Semantics(
              liveRegion: true,
              child: Text(
                s.rateError,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
        ],
        const SizedBox(height: 16),
        if (_saving) const LinearProgressIndicator(),
        FilledButton(
          onPressed: _saving ? null : _done,
          child: Text(s.done),
        ),
      ],
    );
  }
}

class _Stars extends StatelessWidget {
  const _Stars({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var n = 1; n <= 5; n++)
          IconButton(
            tooltip: s.stars(n),
            isSelected: n <= value,
            onPressed: onChanged == null ? null : () => onChanged!(n),
            iconSize: 36,
            icon: const Icon(Icons.star_border_rounded),
            selectedIcon:
                const Icon(Icons.star_rounded, color: Color(0xFFF2A900)),
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      );
}
