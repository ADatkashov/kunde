import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_api/home_services_api.dart';
import 'package:kunde_auth/auth_repository.dart';
import 'package:kunde_mobile/features/home_services/presentation/home_service_reviews.dart';

/// Backend stand-in: one booking that may already have a review, an offer with reviews, optional failures.
class _Session implements AuthRepository {
  _Session({
    this.existing,
    this.failGet = false,
    this.failPost = false,
    this.postStatus,
    this.total = 1,
    this.noRating = false,
  });

  Map<String, dynamic>? existing;
  final bool failGet;
  final bool failPost;
  final int? postStatus;
  final int total;
  final bool noRating;
  final calls = <String>[];
  Map<String, dynamic>? posted;

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
      if (postStatus != null) throw IdentityApiError(postStatus!);
      if (failPost) throw IdentityApiError(500);
      posted = body;
      existing = {
        'id': 'r1',
        'rating': body!['rating'],
        'comment': body['comment'],
        'status': 'PUBLISHED',
      };
      return existing;
    }
    if (failGet) throw IdentityApiError(500);
    if (path.contains('/bookings/')) {
      if (existing == null) throw IdentityApiError(404, 'REVIEW_NOT_FOUND');
      return existing;
    }
    final offset = int.parse(RegExp(r'offset=(\d+)').firstMatch(path)![1]!);
    return {
      'summary': noRating
          ? {'rating': null, 'count': 0}
          : {'rating': 4.5, 'count': total},
      'items': noRating
          ? <Map<String, dynamic>>[]
          : [
              {
                'id': 'r${offset + 1}',
                'rating': 5,
                'comment': 'Отлично ${offset + 1}',
                'authorName': 'Клиент',
              },
            ],
      'total': noRating ? 0 : total,
      'limit': 1,
      'offset': offset,
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(Widget home) => MaterialApp(home: Scaffold(body: home));

void main() {
  test('an offer without reviews has no rating, never zero', () {
    final base = {
      'id': 'o1',
      'serviceId': 's1',
      'venueId': 'v1',
      'venueName': 'Clean Co',
      'definitionCode': 'DEEP_CLEAN',
      'categoryCode': 'CLEANING',
      'nameRu': 'a',
      'nameKk': 'b',
      'nameEn': 'c',
      'priceMinor': 1,
      'pricingModel': 'FIXED',
      'durationMinutes': 60,
      'homeVisit': true,
      'warrantyDays': 0,
    };
    final none = HomeServiceOffer.fromJson(base);
    expect(none.rating, isNull);
    expect(none.reviewCount, 0);
    final rated =
        HomeServiceOffer.fromJson({...base, 'rating': 4.8, 'reviewCount': 12});
    expect(rated.rating, 4.8);
    expect(ratingLabel(rated.rating!, rated.reviewCount), '4.8 (12)');
  });

  testWidgets('a completed order without a review offers to leave one',
      (tester) async {
    final auth = _Session();
    await tester.pumpWidget(
      _app(HomeServiceReviewCard(auth: auth, bookingId: 'b1')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('leave-review')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('leave-review')));
    await tester.pumpAndSettle();
    final submit = find.byKey(const ValueKey('submit-review'));
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('rating-5')));
    await tester.tap(find.byKey(const ValueKey('quality-4')));
    await tester.tap(find.byKey(const ValueKey('punctuality-3')));
    await tester.enterText(
        find.byKey(const ValueKey('review-comment')), '  Быстро и чисто ');
    await tester.pump();
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(auth.posted, {
      'rating': 5,
      'qualityRating': 4,
      'punctualityRating': 3,
      'comment': 'Быстро и чисто',
    });
    // The card now shows the review instead of the button.
    expect(find.byKey(const ValueKey('leave-review')), findsNothing);
    expect(find.text('Быстро и чисто'), findsOneWidget);
  });

  testWidgets('only the overall rating is required', (tester) async {
    final auth = _Session();
    await tester.pumpWidget(
      _app(HomeServiceReviewCard(auth: auth, bookingId: 'b1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('leave-review')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('rating-3')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('submit-review')));
    await tester.pumpAndSettle();
    expect(auth.posted, {'rating': 3});
  });

  testWidgets('an existing review is shown, with the moderation state',
      (tester) async {
    final auth = _Session(existing: {
      'id': 'r1',
      'rating': 4,
      'comment': 'Хорошо',
      'status': 'HIDDEN',
    });
    await tester.pumpWidget(
      _app(HomeServiceReviewCard(auth: auth, bookingId: 'b1')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('leave-review')), findsNothing);
    expect(find.text('Хорошо'), findsOneWidget);
    expect(find.byKey(const ValueKey('review-hidden')), findsOneWidget);
  });

  testWidgets('a failed read offers a retry; a failed send keeps the sheet',
      (tester) async {
    await tester.pumpWidget(
      _app(HomeServiceReviewCard(
          auth: _Session(failGet: true), bookingId: 'b1')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextButton), findsOneWidget);
    expect(find.byKey(const ValueKey('leave-review')), findsNothing);

    final auth = _Session(failPost: true);
    await tester.pumpWidget(
      _app(HomeServiceReviewCard(
          key: const ValueKey('second'), auth: auth, bookingId: 'b2')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('leave-review')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('rating-5')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('submit-review')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('review-error')), findsOneWidget);
    expect(find.byKey(const ValueKey('submit-review')), findsOneWidget);
  });

  testWidgets('an already reviewed order (409) closes the sheet and reloads',
      (tester) async {
    final auth = _Session(postStatus: 409);
    await tester.pumpWidget(
      _app(HomeServiceReviewCard(auth: auth, bookingId: 'b1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('leave-review')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('rating-2')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('submit-review')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('submit-review')), findsNothing);
    expect(
      auth.calls.where((c) => c.startsWith('GET home-services/bookings/b1')),
      hasLength(2),
    );
  });

  testWidgets('reviews screen shows the computed rating and pages on demand',
      (tester) async {
    final auth = _Session(total: 2);
    await tester.pumpWidget(MaterialApp(
      home: HomeServiceReviewsScreen(
        auth: auth,
        path: 'home-services/offers/o1/reviews',
        pageSize: 1,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('summary-rating')), findsOneWidget);
    expect(find.text('4.5'), findsOneWidget);
    expect(find.textContaining('Отлично 1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('more-reviews')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Отлично 2'), findsOneWidget);
    expect(find.byKey(const ValueKey('more-reviews')), findsNothing);
    expect(
      auth.calls.last,
      'GET home-services/offers/o1/reviews?limit=1&offset=1',
    );
  });

  testWidgets('no reviews: an honest empty state, no invented rating',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: HomeServiceReviewsScreen(
        auth: _Session(noRating: true),
        path: 'home-services/masters/m1/reviews',
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('no-reviews')), findsOneWidget);
    expect(find.byKey(const ValueKey('summary-rating')), findsNothing);
  });

  testWidgets('reviews screen: error with retry', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: HomeServiceReviewsScreen(
        auth: _Session(failGet: true),
        path: 'home-services/offers/o1/reviews',
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(TextButton), findsOneWidget);
  });

  testWidgets('stars fit a narrow screen at 200% text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 640),
          textScaler: TextScaler.linear(2),
        ),
        child: Scaffold(
          body: HomeServiceReviewCard(auth: _Session(), bookingId: 'b1'),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
