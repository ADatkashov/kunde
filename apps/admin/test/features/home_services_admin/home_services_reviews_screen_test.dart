import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_admin/features/home_services_admin/home_services_reviews_screen.dart';
import 'package:kunde_auth/auth_repository.dart';

class _Session implements AuthRepository {
  _Session({this.fail = false});

  final bool fail;
  final calls = <String>[];
  final posts = <String, Map<String, dynamic>?>{};

  @override
  Future<dynamic> authorizedJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Set<int> expected = const {200},
    Map<String, String>? headers,
  }) async {
    calls.add('$method $path');
    if (method == 'POST') {
      if (fail) throw Exception('conflict');
      posts[path] = body;
      return <String, dynamic>{};
    }
    if (path.contains('review-complaints')) {
      return [
        {
          'id': 'c1',
          'reviewId': 'r1',
          'reason': 'Оскорбление',
          'status': 'OPEN',
          'reviewRating': 1,
          'reviewComment': 'Грубый текст',
        },
      ];
    }
    return [
      {
        'id': 'r1',
        'bookingNumber': 'KND-100001',
        'serviceName': 'Уборка',
        'masterName': 'Бригада',
        'venueName': 'Clean Co',
        'rating': 1,
        'comment': 'Грубый текст',
        'status': 'PUBLISHED',
        'version': 4,
        'openComplaints': 1,
      },
      {
        'id': 'r2',
        'bookingNumber': 'KND-100002',
        'serviceName': 'Уборка',
        'masterName': 'Бригада',
        'venueName': 'Clean Co',
        'rating': 5,
        'comment': null,
        'status': 'HIDDEN',
        'version': 2,
        'openComplaints': 0,
      },
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _fillReason(WidgetTester tester, String text) async {
  expect(
    tester
        .widget<FilledButton>(find.byKey(const ValueKey('confirm')))
        .onPressed,
    isNull,
  );
  await tester.enterText(find.byKey(const ValueKey('reason')), text);
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('confirm')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('complained review shows the open complaint; hide sends version',
      (tester) async {
    final auth = _Session();
    await tester.pumpWidget(
      MaterialApp(home: HomeServicesReviewsScreen(auth: auth)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('open-r1')), findsOneWidget);
    expect(find.byKey(const ValueKey('open-r2')), findsNothing);
    // A hidden review offers to republish, a published one to hide.
    expect(find.byKey(const ValueKey('hide-r1')), findsOneWidget);
    expect(find.byKey(const ValueKey('publish-r2')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('hide-r1')));
    await tester.pumpAndSettle();
    await _fillReason(tester, 'Нарушает правила');
    expect(auth.posts['admin/home-services/reviews/r1/moderation'], {
      'action': 'HIDE',
      'expectedVersion': 4,
      'reason': 'Нарушает правила',
    });
    expect(
      auth.calls.where((c) => c.startsWith('GET admin/home-services/reviews')),
      hasLength(2),
    );
  });

  testWidgets('republishing needs a reason too', (tester) async {
    final auth = _Session();
    await tester.pumpWidget(
      MaterialApp(home: HomeServicesReviewsScreen(auth: auth)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('publish-r2')));
    await tester.pumpAndSettle();
    await _fillReason(tester, 'Скрыт ошибочно');
    expect(auth.posts['admin/home-services/reviews/r2/moderation'], {
      'action': 'PUBLISH',
      'expectedVersion': 2,
      'reason': 'Скрыт ошибочно',
    });
  });

  testWidgets('complaints: uphold hides the review, dismiss does not',
      (tester) async {
    final auth = _Session();
    await tester.pumpWidget(
      MaterialApp(home: HomeServicesReviewsScreen(auth: auth)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tab-complaints')));
    await tester.pumpAndSettle();
    expect(find.text('Оскорбление'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('uphold-c1')));
    await tester.pumpAndSettle();
    await _fillReason(tester, 'Жалоба обоснована');
    expect(auth.posts['admin/home-services/review-complaints/c1/resolve'], {
      'resolution': 'Жалоба обоснована',
      'hideReview': true,
    });

    await tester.tap(find.byKey(const ValueKey('dismiss-c1')));
    await tester.pumpAndSettle();
    await _fillReason(tester, 'Не подтвердилась');
    expect(auth.posts['admin/home-services/review-complaints/c1/resolve'], {
      'resolution': 'Не подтвердилась',
      'hideReview': false,
    });
  });

  testWidgets('a rejected action shows a message', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: HomeServicesReviewsScreen(auth: _Session(fail: true)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('hide-r1')));
    await tester.pumpAndSettle();
    await _fillReason(tester, 'причина');
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('load failure offers a retry', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: HomeServicesReviewsScreen(auth: _FailingSession()),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(TextButton), findsWidgets);
  });
}

class _FailingSession implements AuthRepository {
  @override
  Future<dynamic> authorizedJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Set<int> expected = const {200},
    Map<String, String>? headers,
  }) async =>
      throw Exception('offline');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
