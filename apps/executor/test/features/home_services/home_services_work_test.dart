import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_auth/auth_repository.dart';
import 'package:kunde_executor/features/home_services/home_services_work_screen.dart';

/// A tiny server: one job that walks CONFIRMED → EN_ROUTE → ARRIVED → IN_PROGRESS → COMPLETED, like the real order rules.
class _Session implements AuthRepository {
  bool linked = false;
  bool offline = false;
  String status = 'CONFIRMED';
  String? stage;
  final calls = <String>[];
  Map<String, dynamic>? stageBody;

  @override
  Future<dynamic> authorizedJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Set<int> expected = const {200},
    Map<String, String>? headers,
  }) async {
    calls.add('$method $path');
    if (path == 'executor/home-services/link') {
      expect(body, {'code': 'HOME-0001'});
      linked = true;
      return null;
    }
    if (!linked) throw IdentityApiError(404, 'NOT_A_MASTER');
    if (offline && method != 'GET') throw IdentityUnavailable();
    if (path.endsWith('/stage')) {
      stageBody = body;
      stage = body!['stage'] as String;
    } else if (path.endsWith('/start')) {
      status = 'IN_PROGRESS';
    } else if (path.endsWith('/complete')) {
      status = 'COMPLETED';
    }
    if (method == 'GET') {
      return status == 'COMPLETED'
          ? []
          : [
              {
                'id': 'j1',
                'serviceName': 'Генеральная уборка',
                'addressText': 'Абая 150',
                'startsAt': '2026-11-27T18:00:00+05:00',
                'status': status,
                'stage': stage,
              },
            ];
    }
    return {};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  offlineTest();
  gpsFailureTest();
  test('the next action follows the booking status and visit stage', () {
    final next = HomeServicesWorkScreen.nextAction;
    expect(next('CONFIRMED', null), 'EN_ROUTE');
    expect(next('CONFIRMED', 'EN_ROUTE'), 'ARRIVED');
    expect(next('CONFIRMED', 'ARRIVED'), 'START');
    expect(next('IN_PROGRESS', 'ARRIVED'), 'COMPLETE');
    expect(next('COMPLETED', 'ARRIVED'), isNull);
  });

  testWidgets(
      'an unlinked account links by code, then walks a visit to the end',
      (tester) async {
    final auth = _Session();
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: const [Locale('en')],
      home: HomeServicesWorkScreen(
          auth: auth,
          readPosition: () async => (latitude: 43.238, longitude: 76.945)),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('code')), 'HOME-0001');
    await tester.tap(find.byKey(const ValueKey('link')));
    await tester.pumpAndSettle();
    expect(find.text('Генеральная уборка'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('eta')), '15');
    await tester.tap(find.byKey(const ValueKey('en_route-j1')));
    await tester.pumpAndSettle();
    expect(auth.stageBody, {
      'stage': 'EN_ROUTE',
      'etaMinutes': 15,
      'latitude': 43.238,
      'longitude': 76.945,
    });

    await tester.tap(find.byKey(const ValueKey('arrived-j1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('start-j1')));
    await tester.pumpAndSettle();
    expect(auth.status, 'IN_PROGRESS');
    await tester.tap(find.byKey(const ValueKey('complete-j1')));
    await tester.pumpAndSettle();
    expect(auth.status, 'COMPLETED');
    expect(find.text('No upcoming jobs'), findsOneWidget);
  });
}

class _NoGps extends _Session {}

void gpsFailureTest() {
  testWidgets('without a position the typed ETA is still sent', (tester) async {
    final auth = _NoGps()..linked = true;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: const [Locale('en')],
      home: HomeServicesWorkScreen(
          auth: auth, readPosition: () async => throw Exception('no gps')),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('en_route-j1')));
    await tester.pumpAndSettle();
    expect(auth.stageBody, {'stage': 'EN_ROUTE', 'etaMinutes': 20});
  });
}

void offlineTest() {
  testWidgets('a lost connection during an action is reported, not swallowed',
      (tester) async {
    final auth = _Session()
      ..linked = true
      ..offline = true;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: const [Locale('en')],
      home: HomeServicesWorkScreen(
          auth: auth, readPosition: () async => throw Exception('no gps')),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('en_route-j1')));
    await tester.pumpAndSettle();
    expect(find.text('No connection. Check the internet and try again.'),
        findsOneWidget);
    expect(auth.stage, isNull);
  });
}
