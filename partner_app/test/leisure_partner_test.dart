import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_partner/core/format.dart';
import 'package:kunde_partner/core/strings.dart';
import 'package:kunde_partner/core/theme.dart';
import 'package:kunde_partner/data/partner_api.dart';
import 'package:kunde_partner/features/leisure/leisure_ops.dart';
import 'package:kunde_partner/features/leisure/leisure_screen.dart';

class _Backend {
  final calls = <String>[];
  final queries = <String>[];
  bool confirmed = false;

  http.Response _json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status,
          headers: {'content-type': 'application/json; charset=utf-8'});

  Map<String, dynamic> order(String status) => {
        'id': '11111111-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        'status': status,
        'sessionId': 's',
        'eventTitle': 'Комната на 2 часа (синтетика)',
        'venueName': 'Демо-караоке',
        'startsAt': '2026-11-22T18:00:00+05:00',
        'guests': 6,
        'totalMinor': 2500000,
        'paymentMethod': 'TEST_CARD',
        'payment': {
          'status': status == 'CONFIRMED' ? 'TEST_CAPTURED' : 'TEST_HELD',
          'refundedMinor': 0
        },
        'reference': '11111111',
        'createdAt': '2026-11-20T10:00:00+05:00',
        'tickets': [],
      };

  Future<http.Response> handle(http.Request r) async {
    calls.add('${r.method} ${r.url.path}');
    queries.add(r.url.query);
    final path =
        r.url.path.replaceFirst('/api/v1/partner/partners/p1/leisure', '');
    if (path == '/stats') {
      return _json({
        'days': 7,
        'orders': 12,
        'tickets': 30,
        'bookedMinor': 124000000,
        'admittedGuests': 21,
        'upcomingSessions': 9
      });
    }
    if (path == '/orders') {
      final scope = r.url.queryParameters['scope'];
      if (scope == 'requests') {
        return _json(confirmed ? [] : [order('PENDING')]);
      }
      return _json([order('CONFIRMED')]);
    }
    if (path == '/orders/11111111-aaaa-aaaa-aaaa-aaaaaaaaaaaa/action') {
      confirmed = true;
      return _json(order('CONFIRMED'));
    }
    if (path == '/venues') return _json([]);
    if (path == '/events') return _json([]);
    return _json({'code': 'NOT_FOUND'}, 404);
  }
}

Widget _app(Widget home, {Locale locale = const Locale('ru')}) => MaterialApp(
      locale: locale,
      theme: buildTheme(Brightness.light),
      supportedLocales: S.supported,
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate
      ],
      home: home,
    );

LeisureOps _ops(_Backend b, {String? product}) => LeisureOps(
    PartnerApi(
        baseUri: Uri.parse('https://api.example.test/api/v1/'),
        accessToken: () async => 'token',
        client: MockClient(b.handle),
        getRetries: 0),
    'p1',
    product: product);

void main() {
  setUp(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('dev.steenbakker.mobile_scanner/scanner/method'),
          (_) async => null));

  testWidgets(
      'overview shows real numbers; a manager can create events, staff cannot',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final b = _Backend();
    await tester
        .pumpWidget(_app(PartnerLeisureScreen(ops: _ops(b), canManage: true)));
    await tester.pumpAndSettle();
    expect(find.text('Досуг'), findsOneWidget);
    expect(find.text(formatMoney(124000000)), findsOneWidget);
    expect(find.text('21'), findsOneWidget);
    expect(find.text('Создать мероприятие'), findsOneWidget);
    expect(find.text('Сканировать QR'), findsOneWidget);
    await tester.pumpWidget(_app(
        PartnerLeisureScreen(ops: _ops(b), canManage: false),
        locale: const Locale('en')));
    await tester.pumpAndSettle();
    expect(find.text('Create event'), findsNothing);
    expect(find.text('Scan QR'), findsOneWidget);
  });

  testWidgets('the Events section is its own product: title and server filter',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final b = _Backend();
    await tester.pumpWidget(_app(PartnerLeisureScreen(
        ops: _ops(b, product: 'EVENTS'), canManage: true)));
    await tester.pumpAndSettle();
    expect(find.text('События'), findsOneWidget);
    expect(find.text('Досуг'), findsNothing);
    expect(b.queries, contains('days=7&product=EVENTS'));
    expect(b.queries.any((q) => q.contains('product=LEISURE')), isFalse);
  });

  testWidgets(
      'a pending booking is confirmed through the server and leaves the requests list',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final b = _Backend();
    await tester
        .pumpWidget(_app(PartnerLeisureScreen(ops: _ops(b), canManage: false)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Бронирования'));
    await tester.tap(find.text('Бронирования'));
    await tester.pumpAndSettle();
    expect(find.text('Комната на 2 часа (синтетика)'), findsOneWidget);
    expect(find.textContaining('#11111111'), findsOneWidget);
    expect(find.textContaining('Тестовая оплата'), findsOneWidget);
    // staff may confirm but is not offered a cancellation of a confirmed booking
    await tester.tap(find.text('Подтвердить'));
    await tester.pumpAndSettle();
    expect(b.calls.any((c) => c.endsWith('/action')), isTrue);
    expect(find.text('Комната на 2 часа (синтетика)'), findsNothing);
    expect(find.text('Пока пусто'), findsOneWidget);
  });
}
