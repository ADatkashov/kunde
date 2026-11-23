import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:kunde_design/kunde_design.dart';

import 'ride_api.dart';
import 'ride_strings.dart';

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
/// payment and rating are not claimed until their backends exist.
class RideCompletedView extends StatelessWidget {
  const RideCompletedView(
      {required this.trip, required this.onDone, super.key});

  final RideTrip trip;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    final theme = Theme.of(context);
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
        const SizedBox(height: 24),
        FilledButton(onPressed: onDone, child: Text(s.done)),
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
