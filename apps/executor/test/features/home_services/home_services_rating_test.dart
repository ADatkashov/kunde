import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_auth/auth_repository.dart';
import 'package:kunde_executor/features/home_services/home_services_rating_screen.dart';

class _Session implements AuthRepository {
  _Session({this.empty = false, this.fail = false});

  final bool empty;
  final bool fail;
  final calls = <String>[];

  @override
  Future<dynamic> authorizedJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Set<int> expected = const {200},
    Map<String, String>? headers,
  }) async {
    calls.add('$method $path');
    if (fail) throw Exception('offline');
    if (path.endsWith('/rating')) {
      return {
        'rating': empty
            ? {
                'rating': null,
                'count': 0,
                'qualityRating': null,
                'punctualityRating': null,
              }
            : {
                'rating': 4.5,
                'count': 2,
                'qualityRating': 4.0,
                'punctualityRating': null,
              },
        'completedOrders': empty ? 3 : 7,
      };
    }
    return {
      'items': empty
          ? <Map<String, dynamic>>[]
          : [
              {'id': 'r1', 'rating': 5, 'comment': 'Быстро'},
              {'id': 'r2', 'rating': 4, 'comment': null},
            ],
      'total': empty ? 0 : 2,
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('shows own rating, details, completed orders and history',
      (tester) async {
    final auth = _Session();
    await tester.pumpWidget(
      MaterialApp(home: HomeServicesRatingScreen(auth: auth)),
    );
    await tester.pumpAndSettle();
    expect(find.text('★ 4.5'), findsOneWidget);
    expect(find.text('Quality: 4.0 · Punctuality: —'), findsOneWidget);
    expect(find.text('Completed orders: 7'), findsOneWidget);
    expect(find.text('Быстро'), findsOneWidget);
    expect(find.byKey(const ValueKey('my-review-r2')), findsOneWidget);
    expect(auth.calls, [
      'GET executor/home-services/rating',
      'GET executor/home-services/reviews?limit=50',
    ]);
  });

  testWidgets('a master without reviews has no rating, but has statistics',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: HomeServicesRatingScreen(auth: _Session(empty: true))),
    );
    await tester.pumpAndSettle();
    expect(find.text('No reviews yet'), findsOneWidget);
    expect(find.text('Completed orders: 3'), findsOneWidget);
    expect(find.textContaining('★'), findsNothing);
  });

  testWidgets('a failed load offers a retry and fits 200% text at 320 dp',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
            size: Size(320, 640), textScaler: TextScaler.linear(2)),
        child: HomeServicesRatingScreen(auth: _Session(fail: true)),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(TextButton), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
