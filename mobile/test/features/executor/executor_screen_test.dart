import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_localization/kunde_localizations.dart';
import 'package:kunde_mobile/features/executor/executor_screen.dart';
import 'package:kunde_auth/auth_repository.dart';

class _DriverSession implements AuthRepository {
  final requests = <String>[];
  bool completed = false;

  @override
  bool get authenticated => true;

  @override
  Future<dynamic> authorizedJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Set<int> expected = const {200},
    Map<String, String>? headers,
  }) async {
    requests.add('$method $path ${body?['step'] ?? ''}');
    switch (path) {
      case 'executor/rides/profile':
        return <String, dynamic>{
          'displayName': 'Test driver',
          'status': 'APPROVED',
          'online': false,
          'vehicle': <String, dynamic>{
            'description': 'Test car',
            'plate': 'TEST1',
            'status': 'APPROVED',
          },
        };
      case 'executor/rides/trips':
        return [
          {
            'id': 'test-trip',
            'status': completed ? 'COMPLETED' : 'IN_PROGRESS',
            'createdAt': '2026-11-18T19:00:00Z',
          }
        ];
      case 'executor/rides/trips/test-trip/progress':
        expect(expected, {204});
        completed = true;
        return null;
      default:
        throw StateError('$method $path');
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  homeTests();
  testWidgets('Executor submits completion and reloads trip history',
      (tester) async {
    _tall(tester);
    final session = _DriverSession();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: KundeLocalizations.supportedLocales,
      localizationsDelegates: KundeLocalizations.localizationsDelegates,
      home: ExecutorScreen(auth: session),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Test driver'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Complete'));
    await tester.pumpAndSettle();
    expect(session.requests,
        contains('POST executor/rides/trips/test-trip/progress COMPLETE'));
    expect(find.text('Ride complete'), findsOneWidget);
  });
}

class _HomeSession implements AuthRepository {
  _HomeSession({this.rating});
  final num? rating;
  final requests = <String>[];

  @override
  bool get authenticated => true;

  @override
  Future<dynamic> authorizedJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Set<int> expected = const {200},
    Map<String, String>? headers,
  }) async {
    requests.add('$method $path');
    final now = DateTime.now().toUtc();
    switch (path) {
      case 'executor/rides/profile':
        return <String, dynamic>{
          'displayName': 'Erlan',
          'status': 'APPROVED',
          'online': false,
          'rating': rating,
          'ratings': rating == null ? 0 : 3,
          'vehicle': <String, dynamic>{
            'description': 'Hyundai Elantra',
            'plate': '774AYA02',
            'status': 'APPROVED',
          },
        };
      case 'executor/rides/offers':
        return <dynamic>[];
      case 'executor/rides/trips':
        return [
          for (final (i, fare) in [1200, 1700].indexed)
            {
              'id': 'done-$i',
              'status': 'COMPLETED',
              'createdAt': now.toIso8601String(),
              'completedAt': now.toIso8601String(),
              'fareKzt': fare,
            },
          {
            'id': 'test-route',
            'status': 'COMPLETED',
            'synthetic': true,
            'createdAt': now.toIso8601String(),
            'completedAt': now.toIso8601String(),
            'fareKzt': 5000,
          },
          {
            'id': 'old',
            'status': 'COMPLETED',
            'createdAt': '2020-01-01T10:00:00Z',
            'completedAt': '2020-01-01T10:20:00Z',
            'fareKzt': 900,
          },
        ];
      case 'executor/rides/availability':
        return <String, dynamic>{};
      default:
        throw StateError('$method $path');
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget _home(AuthRepository auth) => MaterialApp(
      locale: const Locale('en'),
      supportedLocales: KundeLocalizations.supportedLocales,
      localizationsDelegates: KundeLocalizations.localizationsDelegates,
      home: ExecutorScreen(auth: auth),
    );

void homeTests() {
  testWidgets('home shows real income, rides, rating and the reference menu',
      (tester) async {
    _tall(tester);
    await tester.pumpWidget(_home(_HomeSession(rating: 4.9)));
    await tester.pumpAndSettle();
    // 1 200 + 1 700 today; the test route and the 2020 ride do not count.
    expect(
        tester.widget<Text>(find.byKey(const Key('executor-today-fare'))).data,
        '2 900 ₸');
    expect(
        tester.widget<Text>(find.byKey(const Key('executor-today-trips'))).data,
        '3');
    expect(tester.widget<Text>(find.byKey(const Key('executor-rating'))).data,
        '4.90');
    expect(find.text('Online'), findsOneWidget);
    expect(find.text('Get an order'), findsOneWidget);
    for (final label in [
      'My rides',
      'Income and payouts',
      'Statistics',
      'Support'
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    for (final label in ['Home', 'Orders', 'Income', 'Profile']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('rating is a dash until the first customer rating',
      (tester) async {
    _tall(tester);
    await tester.pumpWidget(_home(_HomeSession()));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('executor-rating'))).data,
        '—');
  });

  testWidgets('Get an order goes online while offline', (tester) async {
    _tall(tester);
    final session = _HomeSession();
    await tester.pumpWidget(_home(session));
    await tester.pumpAndSettle();
    expect(find.byType(Switch), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  testWidgets('income tab shows the 7 day estimate and payout note',
      (tester) async {
    _tall(tester);
    await tester.pumpWidget(_home(_HomeSession(rating: 5)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Income').last);
    await tester.pumpAndSettle();
    expect(
        tester.widget<Text>(find.byKey(const Key('executor-week-fare'))).data,
        '2 900 ₸');
    expect(find.textContaining('payouts are not connected'), findsOneWidget);
  });
}
