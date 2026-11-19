import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_mobile/core/localization/kunde_localizations.dart';
import 'package:kunde_mobile/features/executor/auto_work_screen.dart';
import 'package:kunde_mobile/features/identity/auth_repository.dart';

/// In-memory AUTO_SPECIALIST backend behind the AuthRepository seam.
class _SpecialistSession implements AuthRepository {
  _SpecialistSession({this.kind = 'APPROVED'});

  Map<String, dynamic>? savedProfile;
  String kind;
  bool online = true;
  final calls = <String>[];
  final bodies = <Map<String, dynamic>?>[];
  Map<String, dynamic>? job;
  bool open = true;
  bool taken = false;

  Map<String, dynamic> get _profile =>
      savedProfile ??
      {
        'name': 'Тест Специалист',
        'status': kind,
        'online': online,
        'categories': ['ROADSIDE']
      };

  @override
  Future<dynamic> authorizedJson(String method, String path,
      {Map<String, dynamic>? body,
      Set<int> expected = const {200},
      Map<String, String>? headers}) async {
    calls.add('$method $path');
    bodies.add(body);
    switch ((method, path)) {
      case ('GET', 'executor/auto/profile'):
        if (savedProfile == null && kind == 'NONE') {
          throw IdentityApiError(404, 'SPECIALIST_NOT_FOUND');
        }
        return _profile;
      case ('POST', 'executor/auto/profile'):
        kind = 'PENDING';
        savedProfile = {
          'name': body!['name'],
          'status': 'PENDING',
          'online': false,
          'categories': []
        };
        return savedProfile;
      case ('PUT', 'executor/auto/availability'):
        online = body!['online'] as bool;
        savedProfile = {..._profile, 'online': online};
        return savedProfile;
      case ('PUT', 'executor/auto/location'):
        return null;
      case ('GET', 'executor/auto/jobs/available'):
        return open && job == null
            ? [
                {
                  'id': 'job-1',
                  'vehicle': 'Toyota Camry 2018',
                  'category': 'ROADSIDE',
                  'description': 'Не заводится',
                  'priceMinor': 1500000,
                  'distanceKm': 2.4,
                  'allowedActions': ['ACCEPT']
                }
              ]
            : [];
      case ('GET', 'executor/auto/jobs'):
        return job == null ? [] : [job];
      case ('POST', 'executor/auto/jobs/job-1/accept'):
        if (taken) throw IdentityApiError(409, 'JOB_TAKEN');
        job = _job('ASSIGNED', ['ARRIVE', 'RELEASE']);
        return job;
      case ('POST', 'executor/auto/jobs/job-1/progress'):
        final action = body!['action'] as String;
        job = switch (action) {
          'ARRIVE' => _job('ARRIVED', ['START']),
          'START' => _job('IN_PROGRESS', ['PROPOSE_PRICE', 'COMPLETE']),
          'PROPOSE_PRICE' => {
              ..._job('IN_PROGRESS', ['PROPOSE_PRICE']),
              'finalPriceMinor': body['finalPriceMinor'],
              'priceApproval': 'PENDING'
            },
          'COMPLETE' => _job('COMPLETED', []),
          _ => throw StateError('unexpected $action'),
        };
        return job;
    }
    throw StateError('Unexpected API call $method $path');
  }

  Map<String, dynamic> _job(String status, List<String> actions) => {
        'id': 'job-1',
        'vehicle': 'Toyota Camry 2018',
        'category': 'ROADSIDE',
        'description': 'Не заводится',
        'addressText': 'Алматы, ул. Тестовая 5',
        'status': status,
        'priceMinor': 1500000,
        'priceKind': 'FROM',
        'allowedActions': actions,
      };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(AuthRepository auth,
        {bool intake = true, Locale locale = const Locale('ru')}) =>
    MaterialApp(
      locale: locale,
      supportedLocales: KundeLocalizations.supportedLocales,
      localizationsDelegates: KundeLocalizations.localizationsDelegates,
      home: AutoWorkScreen(auth: auth, synthetic: true, intakeEnabled: intake),
    );

void main() {
  setUp(() {});

  void tall(WidgetTester t) {
    t.view.physicalSize = const Size(900, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }

  testWidgets('new user enrolls and sees the review status', (tester) async {
    tall(tester);
    final s = _SpecialistSession(kind: 'NONE');
    await tester.pumpWidget(_app(s));
    await tester.pumpAndSettle();
    expect(find.text('Отправить на проверку'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Тест Специалист');
    await tester.tap(find.text('Отправить на проверку'));
    await tester.pumpAndSettle();
    expect(s.calls, contains('POST executor/auto/profile'));
    expect(find.text('На проверке'), findsOneWidget);
    expect(find.text('Принимаю заявки'), findsNothing,
        reason: 'a pending specialist cannot go online');
  });

  testWidgets(
      'approved specialist accepts a nearby job and runs it to completion',
      (tester) async {
    tall(tester);
    final s = _SpecialistSession();
    await tester.pumpWidget(_app(s));
    await tester.pumpAndSettle();
    expect(find.textContaining('2.4 km'), findsOneWidget);
    expect(find.textContaining('Алматы, ул. Тестовая'), findsNothing,
        reason: 'the address is hidden before accepting');
    await tester.tap(find.text('Принять'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Алматы, ул. Тестовая 5'), findsOneWidget);
    await tester.tap(find.text('Я на месте'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Начать работы'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Предложить цену'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '99999999');
    await tester.pump();
    expect(find.text('От 0 до 1 000 000 ₸'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '25000');
    await tester.pump();
    await tester.tap(find.text('Предложить'));
    await tester.pumpAndSettle();
    final idx = s.calls.lastIndexOf('POST executor/auto/jobs/job-1/progress');
    expect(
        s.bodies[idx], {'action': 'PROPOSE_PRICE', 'finalPriceMinor': 2500000});
    expect(find.textContaining('ждёт согласия клиента'), findsOneWidget);
    expect(find.text('Завершить'), findsNothing,
        reason: 'completion waits for the customer approval');
  });

  testWidgets('a job taken by someone else shows a clear message',
      (tester) async {
    tall(tester);
    final s = _SpecialistSession()..taken = true;
    await tester.pumpWidget(_app(s));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Принять'));
    await tester.pumpAndSettle();
    expect(find.text('Заявку уже взял другой специалист.'), findsOneWidget);
  });

  testWidgets(
      'with Auto switched off no new jobs are offered but assigned work is shown',
      (tester) async {
    tall(tester);
    final s = _SpecialistSession();
    s.job = s._job('ARRIVED', ['START']);
    await tester.pumpWidget(_app(s, intake: false, locale: const Locale('en')));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('New requests are switched off'), findsOneWidget);
    expect(find.text('Nearby requests'), findsNothing);
    expect(s.calls, isNot(contains('GET executor/auto/jobs/available')));
    expect(find.text('Start work'), findsOneWidget);
  });
}
