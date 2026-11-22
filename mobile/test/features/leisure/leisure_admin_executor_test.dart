import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_mobile/core/localization/kunde_localizations.dart';
import 'package:kunde_mobile/features/executor/gate_scan_screen.dart';
import 'package:kunde_mobile/features/executor/leisure_work_screen.dart';
import 'package:kunde_mobile/features/identity/auth_repository.dart';
import 'package:kunde_mobile/features/leisure/data/leisure_models.dart';
import 'package:kunde_mobile/features/leisure_admin/leisure_admin_screen.dart';

class _Vault implements TokenVault {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async {}
  @override
  Future<void> clear() async {}
}

class _Gateway implements OAuthGateway {
  @override
  Future<AuthTokens> login({bool register = false}) async => AuthTokens(
      'access',
      'refresh',
      null,
      DateTime.now().add(const Duration(minutes: 5)));
  @override
  Future<AuthTokens> refresh(String refreshToken) => login();
  @override
  Future<void> logout(String? idToken) async {}
}

class _Backend {
  final calls = <String>[];
  final bodies = <String>[];
  bool venuePending = true;
  bool offline = false;
  String gateResult = 'ADMITTED';
  String assignment = 'OFFERED';

  http.Response _json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status,
          headers: {'content-type': 'application/json; charset=utf-8'});

  Map<String, dynamic> get _assignment => {
        'id': 'as-1',
        'status': assignment,
        'role': 'GUIDE',
        'note': 'Встреча у фонтана',
        'sessionId': 's',
        'eventTitle': 'Пешая экскурсия по центру (синтетика)',
        'venueName': 'Демо-экскурсии',
        'venueAddress': 'Старт у фонтана',
        'startsAt': '2026-11-22T10:00:00+05:00',
        'endsAt': '2026-11-22T12:00:00+05:00',
        'guests': 7,
        'executor': '•••0522',
        'canStart': false,
        'canComplete': false,
      };

  final queries = <String>[];

  Future<http.Response> handle(http.Request r) async {
    final path = r.url.path.replaceFirst('/api/v1/', '');
    calls.add('${r.method} $path');
    queries.add(r.url.query);
    if (r.body.isNotEmpty) bodies.add(r.body);
    if (path == 'executor/leisure/checkins' && r.method == 'POST') {
      if (offline) throw http.ClientException('offline');
      return _json({
        'result': gateResult,
        'admitted': gateResult == 'ADMITTED',
        'message': 'm',
        'eventTitle': gateResult == 'ADMITTED' ? 'Демо-фильм' : null,
        'seat': gateResult == 'ADMITTED' ? 'D5' : null,
      });
    }
    if (path == 'admin/leisure/summary') {
      return _json({
        'events': 9,
        'venues': 8,
        'partners': 2,
        'orders': 41,
        'tickets': 77,
        'bookedMinor': 42600000,
        'refundedMinor': 500000,
        'admittedGuests': 33,
        'pendingVenues': venuePending ? 1 : 0,
        'pendingEvents': 0,
        'openComplaints': 2,
        'perDay': [
          for (var i = 0; i < 7; i++)
            {
              'day': '2026-11-${14 + i}',
              'orders': i * 3,
              'bookedMinor': i * 1000
            }
        ],
      });
    }
    if (path == 'admin/leisure/venues') {
      return _json(venuePending
          ? [
              {
                'id': 'v1',
                'name': 'Новая площадка (синтетика)',
                'partner': 'Демо-партнёр Б',
                'district': 'Медеуский',
                'status': 'PENDING',
                'moderationNote': null,
                'events': 0,
                'createdAt': '2026-11-20T10:00:00+05:00',
                'synthetic': true
              }
            ]
          : []);
    }
    if (path == 'admin/leisure/venues/v1/decision') {
      venuePending = false;
      return _json({'id': 'v1', 'status': 'APPROVED'});
    }
    if (path == 'executor/leisure/assignments' && r.method == 'GET') {
      return _json(
          r.url.queryParameters['scope'] == 'history' ? [] : [_assignment]);
    }
    if (path == 'executor/leisure/assignments/as-1/step') {
      assignment = 'ACCEPTED';
      return _json(_assignment);
    }
    return _json({'code': 'NOT_FOUND'}, 404);
  }
}

Future<AuthRepository> _auth(_Backend b) async {
  final auth = AuthRepository(
      gateway: _Gateway(),
      vault: _Vault(),
      apiBase: Uri.parse('https://api.example.test/api/v1/'),
      client: MockClient(b.handle));
  await auth.signIn(AuthTokens('access', 'refresh', null,
      DateTime.now().add(const Duration(minutes: 5))));
  addTearDown(auth.dispose);
  return auth;
}

Widget _app(Widget home, {Locale locale = const Locale('ru')}) => MaterialApp(
      locale: locale,
      supportedLocales: KundeLocalizations.supportedLocales,
      localizationsDelegates: KundeLocalizations.localizationsDelegates,
      home: home,
    );

void main() {
  setUp(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('dev.steenbakker.mobile_scanner/scanner/method'),
          (_) async => null));

  testWidgets(
      'gate scan: the server decides - admitted, denied, and a lost network is never "valid"',
      (tester) async {
    final b = _Backend();
    await tester.pumpWidget(_app(GateScanScreen(auth: await _auth(b))));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'KT1.x');
    await tester.tap(find.text('Проверить'));
    await tester.pumpAndSettle();
    expect(find.text('Проход разрешён'), findsOneWidget);
    expect(find.text('Демо-фильм'), findsOneWidget);
    expect(b.bodies.last, contains('KT1.x'));
    await tester.tap(find.text('Следующий'));
    await tester.pump();
    b.gateResult = 'ACCESS_DENIED';
    await tester.enterText(find.byType(TextField), 'KT1.y');
    await tester.tap(find.text('Проверить'));
    await tester.pumpAndSettle();
    expect(find.text('Нет доступа к этому сеансу'), findsOneWidget);
    expect(find.text('Проход разрешён'), findsNothing);
    await tester.tap(find.text('Следующий'));
    await tester.pump();
    b.offline = true;
    await tester.enterText(find.byType(TextField), 'KT1.z');
    await tester.tap(find.text('Проверить'));
    await tester.pumpAndSettle();
    expect(find.textContaining('не проверен'), findsOneWidget);
    expect(find.text('Проход разрешён'), findsNothing);
  });

  testWidgets(
      'admin overview shows server numbers and the chart; moderation approves a pending venue with an audit-bearing request',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final b = _Backend();
    await tester.pumpWidget(_app(LeisureAdminScreen(auth: await _auth(b))));
    await tester.pumpAndSettle();
    expect(find.text('41'), findsOneWidget);
    expect(find.text(formatTenge(42600000)), findsOneWidget);
    expect(find.text('Бронирования по дням'), findsOneWidget);
    await tester.tap(find.text('Модерация'));
    await tester.pumpAndSettle();
    expect(find.text('Новая площадка (синтетика)'), findsOneWidget);
    expect(find.text('синтетика (DEV)'), findsOneWidget);
    await tester.tap(find.text('Одобрить'));
    await tester.pumpAndSettle();
    expect(b.calls, contains('POST admin/leisure/venues/v1/decision'));
    expect(b.bodies.last, contains('APPROVE'));
    expect(find.text('Пусто'), findsOneWidget);
  });

  testWidgets(
      'Events control center asks the server for the Events product only',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final b = _Backend();
    await tester.pumpWidget(
        _app(LeisureAdminScreen(auth: await _auth(b), product: 'EVENTS')));
    await tester.pumpAndSettle();
    expect(find.text('События: центр управления'), findsOneWidget);
    expect(b.queries, contains('days=14&product=EVENTS'));
    await tester.tap(find.text('Брони'));
    await tester.pumpAndSettle();
    expect(b.queries.any((q) => q.contains('product=EVENTS')), isTrue);
    await tester.tap(find.text('Жалобы'));
    await tester.pumpAndSettle();
    expect(
        b.queries.any((q) =>
            q.contains('includeResolved') && q.contains('product=EVENTS')),
        isTrue);
    expect(b.queries.where((q) => q.contains('product=LEISURE')), isEmpty);
  });

  testWidgets('a forbidden admin sees a retry state, not data', (tester) async {
    final b = _Backend();
    final auth = AuthRepository(
        gateway: _Gateway(),
        vault: _Vault(),
        apiBase: Uri.parse('https://api.example.test/api/v1/'),
        client: MockClient((_) async => http.Response(
            '{"code":"ADMIN_FORBIDDEN"}', 403,
            headers: {'content-type': 'application/json'})));
    await auth.signIn(AuthTokens('access', 'refresh', null,
        DateTime.now().add(const Duration(minutes: 5))));
    addTearDown(auth.dispose);
    await tester.pumpWidget(_app(LeisureAdminScreen(auth: auth)));
    await tester.pumpAndSettle();
    expect(find.text('Повторить'), findsOneWidget);
    expect(b.calls, isEmpty);
  });

  testWidgets(
      'executor accepts an offered assignment; start stays disabled outside the work window',
      (tester) async {
    final b = _Backend();
    await tester.pumpWidget(_app(LeisureWorkScreen(auth: await _auth(b))));
    await tester.pumpAndSettle();
    expect(find.text('Пешая экскурсия по центру (синтетика)'), findsOneWidget);
    expect(find.textContaining('Гид'), findsOneWidget);
    await tester.tap(find.text('Принять'));
    await tester.pumpAndSettle();
    expect(b.bodies.last, contains('ACCEPT'));
    expect(find.text('Принято'), findsOneWidget);
    final start = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Начать'));
    expect(start.onPressed, isNull);
  });
}
