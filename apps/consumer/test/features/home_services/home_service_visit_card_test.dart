import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_mobile/features/home_services/presentation/home_service_visit_card.dart';

Widget _app(Future<Map<String, dynamic>> Function() load) => MaterialApp(
      locale: const Locale('en'),
      supportedLocales: const [Locale('en')],
      home: Scaffold(
          body: HomeServiceVisitCard(
              load: load, every: const Duration(seconds: 1))),
    );

void main() {
  testWidgets('the customer approves only the displayed schedule version',
      (tester) async {
    var decided = false;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      home: Scaffold(
        body: HomeServiceVisitCard(
          load: () async => {
            'status': 'CONFIRMED',
            if (!decided)
              'reschedule': {
                'startsAt': '2026-12-01T06:00:00Z',
                'reason': 'New time',
                'version': 3,
              }
          },
          decideReschedule: (version, accepted) async {
            expect(version, 3);
            expect(accepted, isTrue);
            decided = true;
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('New time proposed'), findsOneWidget);
    await tester.tap(find.text('Confirm change'));
    await tester.pumpAndSettle();
    expect(decided, isTrue);
    expect(find.text('New time proposed'), findsNothing);
  });

  testWidgets('shows the master on the way with the ETA, then on site',
      (tester) async {
    var visit = {'status': 'CONFIRMED', 'stage': 'EN_ROUTE', 'etaMinutes': 12};
    await tester.pumpWidget(_app(() async => visit));
    await tester.pump();
    expect(find.text('The master is on the way, arriving in ~12 min'),
        findsOneWidget);

    visit = {'status': 'CONFIRMED', 'stage': 'ARRIVED', 'etaMinutes': 0};
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('The master has arrived'), findsOneWidget);

    visit = {'status': 'IN_PROGRESS', 'stage': 'ARRIVED', 'etaMinutes': 0};
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('The master is working'), findsOneWidget);
  });

  testWidgets(
      'a failed read keeps the last state and a missing visit hides the card',
      (tester) async {
    var fail = false;
    await tester.pumpWidget(_app(() async {
      if (fail) throw Exception('offline');
      return {'status': 'CONFIRMED', 'stage': null, 'etaMinutes': null};
    }));
    await tester.pump();
    expect(find.text('The master will come at the scheduled time'),
        findsOneWidget);
    fail = true;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('The master will come at the scheduled time'),
        findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app(() async => throw Exception('offline')));
    await tester.pump();
    expect(find.byKey(const ValueKey('visit-card')), findsNothing);
  });
}
