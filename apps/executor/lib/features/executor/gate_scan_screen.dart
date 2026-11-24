import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:kunde_auth/auth_repository.dart';
import 'package:kunde_ui/ride_strings.dart';

/// Gate control of KUNDE Events for an executor assigned by the organiser as GATE controller. The camera only reads the code: the server
/// decides (assignment, ticket, session, status, repeat, time window) and admits a ticket exactly once. Nothing is decided on the device and
/// an unreadable network is shown as such, never as "valid".
class GateScanScreen extends StatefulWidget {
  const GateScanScreen({required this.auth, super.key});

  final AuthRepository auth;

  @override
  State<GateScanScreen> createState() => _GateScanScreenState();
}

class _GateScanScreenState extends State<GateScanScreen> {
  final MobileScannerController _camera = MobileScannerController(
      formats: const [BarcodeFormat.qrCode],
      detectionSpeed: DetectionSpeed.noDuplicates);
  final _manual = TextEditingController();
  Map<String, dynamic>? _result;
  bool _busy = false;
  bool _offline = false;
  String? _lastCode;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    _camera.dispose();
    _manual.dispose();
    super.dispose();
  }

  Future<void> _check(String code) async {
    if (_busy || code.trim().isEmpty) return;
    final now = DateTime.now();
    if (code == _lastCode &&
        now.difference(_lastAt) < const Duration(seconds: 3)) {
      return;
    }
    _lastCode = code;
    _lastAt = now;
    setState(() {
      _busy = true;
      _offline = false;
    });
    try {
      final r = await widget.auth.authorizedJson(
              'POST', 'executor/leisure/checkins', body: {'code': code.trim()})
          as Map<String, dynamic>;
      if (mounted) setState(() => _result = r);
    } catch (_) {
      if (mounted) setState(() => _offline = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String outcome(RideStrings s, String result) => switch (result) {
        'ADMITTED' => s.t('Проход разрешён', 'Кіруге рұқсат', 'Admitted'),
        'DUPLICATE' =>
          s.t('Билет уже использован', 'Билет пайдаланылған', 'Already used'),
        'INVALID' =>
          s.t('Недействительный код', 'Жарамсыз код', 'Invalid code'),
        'ACCESS_DENIED' => s.t('Нет доступа к этому сеансу',
            'Бұл сеансқа қолжетім жоқ', 'You are not assigned to this session'),
        'WRONG_SESSION' =>
          s.t('Другой сеанс', 'Басқа сеанс', 'Another session'),
        'CANCELLED' => s.t(
            'Билет отменён или возвращён',
            'Билет бас тартылған немесе қайтарылған',
            'Ticket cancelled or refunded'),
        'NOT_CONFIRMED' => s.t('Заказ не подтверждён', 'Тапсырыс расталмаған',
            'Order not confirmed'),
        'EXPIRED' =>
          s.t('Сеанс уже прошёл', 'Сеанс өтіп кеткен', 'The session is over'),
        'TOO_EARLY' => s.t('Вход пока не открыт', 'Кіру әлі ашылмаған',
            'Entry is not open yet'),
        _ => result,
      };

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    final theme = Theme.of(context);
    final result = _result;
    final ok = result?['admitted'] == true;
    return Scaffold(
      appBar: AppBar(
          title: Text(
              s.t('Проверка билетов', 'Билеттерді тексеру', 'Ticket check'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (result != null)
          Semantics(
            liveRegion: true,
            child: Card(
              color: (ok ? Colors.green : theme.colorScheme.error)
                  .withValues(alpha: .12),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(children: [
                  Icon(ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
                      size: 72,
                      color: ok ? Colors.green : theme.colorScheme.error),
                  const SizedBox(height: 12),
                  Text(outcome(s, '${result['result']}'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  if (result['eventTitle'] != null)
                    Text('${result['eventTitle']}',
                        textAlign: TextAlign.center),
                  if (result['seat'] != null || result['ticketType'] != null)
                    Text([result['seat'], result['ticketType']]
                        .whereType<String>()
                        .join(' · ')),
                  const SizedBox(height: 16),
                  FilledButton(
                      onPressed: () => setState(() => _result = null),
                      child: Text(s.t('Следующий', 'Келесі', 'Next'))),
                ]),
              ),
            ),
          )
        else
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
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
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.no_photography_outlined, size: 40),
                          const SizedBox(height: 8),
                          Text(
                              s.t(
                                  'Нет доступа к камере. Введите код вручную.',
                                  'Камераға рұқсат жоқ. Кодты қолмен енгізіңіз.',
                                  'No camera access. Type the code instead.'),
                              textAlign: TextAlign.center),
                          const SizedBox(height: 8),
                          OutlinedButton(
                              onPressed: () => unawaited(_camera.start()),
                              child:
                                  Text(s.t('Повторить', 'Қайталау', 'Retry'))),
                        ]),
                  ),
                ),
                if (_busy) const Center(child: CircularProgressIndicator()),
              ]),
            ),
          ),
        if (_offline)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
                s.t(
                    'Нет связи с сервером: билет не проверен. Повторите.',
                    'Серверге қосылым жоқ: билет тексерілмеді. Қайталаңыз.',
                    'No connection: the ticket was NOT checked. Try again.'),
                style: TextStyle(color: theme.colorScheme.error)),
          ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
              child: TextField(
                  controller: _manual,
                  decoration: InputDecoration(
                      labelText:
                          s.t('Код вручную', 'Кодты қолмен', 'Code (manual)'),
                      border: const OutlineInputBorder()))),
          const SizedBox(width: 8),
          FilledButton(
              onPressed: _busy ? null : () => _check(_manual.text),
              child: Text(s.t('Проверить', 'Тексеру', 'Check'))),
        ]),
      ]),
    );
  }
}
