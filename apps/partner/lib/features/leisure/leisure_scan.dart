import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/error_text.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import 'leisure_ops.dart';
import 'leisure_screen.dart' show shortWhen;
import 'leisure_strings.dart';

/// QR check-in. The camera only reads the code; the server decides (organiser, session, status, repeat, time window) and answers with the
/// outcome that is shown here. A code can also be typed. Camera permission is requested by the scanner and a refusal falls back to typing.
class LeisureScanner extends StatefulWidget {
  const LeisureScanner({required this.ops, super.key});

  final LeisureOps ops;

  @override
  State<LeisureScanner> createState() => _LeisureScannerState();
}

class _LeisureScannerState extends State<LeisureScanner> {
  final MobileScannerController _camera = MobileScannerController(
      formats: const [BarcodeFormat.qrCode],
      detectionSpeed: DetectionSpeed.noDuplicates);
  final _manual = TextEditingController();
  Map<String, dynamic>? _result;
  bool _busy = false;
  String? _error;
  late Future<List<Map<String, dynamic>>> _recent = widget.ops.checkins();
  String? _lastCode;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    _camera.dispose();
    _manual.dispose();
    super.dispose();
  }

  Future<void> _check(String code) async {
    if (_busy) return;
    final now = DateTime.now();
    if (code == _lastCode &&
        now.difference(_lastAt) < const Duration(seconds: 3)) {
      return;
    }
    _lastCode = code;
    _lastAt = now;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await widget.ops.checkin(code.trim());
      if (!mounted) return;
      setState(() {
        _result = r;
        _recent = widget.ops.checkins();
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorText(S.of(context), e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final result = _result;
    return ListView(padding: const EdgeInsets.all(Gap.lg), children: [
      if (result != null)
        _ResultCard(
            result: result, onNext: () => setState(() => _result = null))
      else ...[
        ClipRRect(
          borderRadius: BorderRadius.circular(Radii.card),
          child: SizedBox(
            height: 300,
            child: Stack(fit: StackFit.expand, children: [
              MobileScanner(
                controller: _camera,
                onDetect: (capture) {
                  final code = capture.barcodes
                      .map((b) => b.rawValue)
                      .whereType<String>()
                      .firstOrNull;
                  if (code != null) unawaited(_check(code));
                },
                errorBuilder: (context, error) => Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                  padding: const EdgeInsets.all(Gap.lg),
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.no_photography_outlined, size: 40),
                        const SizedBox(height: Gap.sm),
                        Text(s.lzCameraDenied, textAlign: TextAlign.center),
                        const SizedBox(height: Gap.sm),
                        OutlinedButton(
                            onPressed: () => unawaited(_camera.start()),
                            child: Text(s.lzCameraRetry)),
                      ]),
                ),
              ),
              IgnorePointer(
                child: Center(
                    child: Container(
                        width: 190,
                        height: 190,
                        decoration: BoxDecoration(
                            border: Border.all(color: Colors.white, width: 3),
                            borderRadius: BorderRadius.circular(20)))),
              ),
              if (_busy) const Center(child: CircularProgressIndicator()),
            ]),
          ),
        ),
        const SizedBox(height: Gap.sm),
        Text(s.lzCamera,
            textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
      ],
      if (_error != null)
        Padding(
            padding: const EdgeInsets.only(top: Gap.md),
            child: Text(_error!,
                style: TextStyle(color: theme.colorScheme.error))),
      const SizedBox(height: Gap.lg),
      Row(children: [
        Expanded(
            child: TextField(
                controller: _manual,
                decoration: InputDecoration(
                    labelText: s.lzManualCode,
                    border: const OutlineInputBorder()))),
        const SizedBox(width: Gap.sm),
        FilledButton(
            onPressed: _busy ? null : () => _check(_manual.text),
            child: Text(s.lzCheck)),
      ]),
      const SizedBox(height: Gap.xl),
      Text(s.lzRecent,
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w800)),
      FutureBuilder<List<Map<String, dynamic>>>(
        future: _recent,
        builder: (context, snap) {
          if (!snap.hasData) return const SizedBox(height: 40);
          return Column(children: [
            for (final c in snap.data!.take(10))
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(
                    c['result'] == 'ADMITTED'
                        ? Icons.check_circle_rounded
                        : Icons.cancel_rounded,
                    color: c['result'] == 'ADMITTED'
                        ? context.tones.success
                        : theme.colorScheme.error),
                title: Text(s.lzCheckResult('${c['result']}')),
                subtitle: Text(
                    '${c['eventTitle'] ?? ''} · ${shortWhen('${c['at']}')}'),
              ),
          ]);
        },
      ),
    ]);
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result, required this.onNext});

  final Map<String, dynamic> result;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final ok = result['admitted'] == true;
    final color =
        ok ? context.tones.success : Theme.of(context).colorScheme.error;
    return Semantics(
      liveRegion: true,
      child: Card(
        color: color.withValues(alpha: .12),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.card),
            side: BorderSide(color: color, width: 2)),
        child: Padding(
          padding: const EdgeInsets.all(Gap.xl),
          child: Column(children: [
            Icon(ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
                size: 72, color: color),
            const SizedBox(height: Gap.md),
            Text(s.lzCheckResult('${result['result']}'),
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w900, color: color)),
            const SizedBox(height: Gap.sm),
            if (result['eventTitle'] != null)
              Text('${result['eventTitle']}', textAlign: TextAlign.center),
            if (result['startsAt'] != null)
              Text(shortWhen('${result['startsAt']}')),
            if (result['seat'] != null)
              Text('${s.lzSeatsLabel}: ${result['seat']}'),
            if (ok) Text('${s.lzGuests}: ${result['admits']}'),
            if (result['usedAt'] != null && result['result'] == 'DUPLICATE')
              Text(shortWhen('${result['usedAt']}')),
            const SizedBox(height: Gap.lg),
            FilledButton.icon(
                onPressed: onNext,
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: Text(s.lzNext)),
          ]),
        ),
      ),
    );
  }
}
