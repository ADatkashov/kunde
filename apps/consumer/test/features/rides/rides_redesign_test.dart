import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_localization/kunde_localizations.dart';
import 'package:kunde_auth/auth_repository.dart';
import 'package:kunde_api/ride_api.dart';
import 'package:kunde_mobile/features/rides/rides_hub_screen.dart';
import 'package:kunde_mobile/features/rides/rides_screen.dart';

class _Auth implements AuthRepository {
  _Auth({this.history = const []});

  final List<Map<String, dynamic>> history;
  final calls = <String>[];
  final ratings = <Map<String, dynamic>?>[];

  static Map<String, dynamic> trip(String status, {bool driver = false}) => {
        'id': 'trip-1',
        'status': status,
        'estimateKzt': 1200,
        'createdAt': '2026-11-22T10:00:00Z',
        'synthetic': false,
        if (driver)
          'driver': {
            'name': 'Erlan',
            'vehicle': 'Hyundai Elantra',
            'plate': '774 AYA 02'
          },
      };

  @override
  Future<dynamic> authorizedJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Set<int> expected = const {200},
    Map<String, String>? headers,
  }) async {
    calls.add('$method $path');
    switch ((method, path)) {
      case ('POST', 'rides/address-search'):
        return [
          {
            'address': 'Abay 10',
            'point': {'latitude': 43.238, 'longitude': 76.945},
          },
        ];
      case ('POST', 'rides/quotes'):
        return {
          'id': 'quote-1',
          'estimateKzt': 1200,
          'distanceMeters': 5400,
          'durationSeconds': 720,
          'synthetic': false,
        };
      case ('POST', 'rides'):
        return trip('REQUESTED');
      case ('POST', 'rides/trip-1/dispatch'):
        return trip('SEARCHING_DRIVER');
      case ('POST', 'rides/trip-1/rating'):
        ratings.add(body);
        return {'rideId': 'trip-1', 'stars': body!['stars']};
      case ('GET', 'rides'):
        return history;
    }
    throw StateError('Unexpected call $method $path');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(Widget home, {String language = 'en'}) => MaterialApp(
      locale: Locale(language),
      supportedLocales: KundeLocalizations.supportedLocales,
      localizationsDelegates: KundeLocalizations.localizationsDelegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: home,
    );

Future<void> _pickBoth(WidgetTester tester) async {
  for (final label in ['Pickup', 'Destination']) {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Abay');
    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abay 10').last);
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('hub lists five categories; only city rides is available',
      (tester) async {
    await tester.pumpWidget(_app(RidesHubScreen(api: RideApi(_Auth()))));
    for (final title in [
      'City rides',
      'To the airport',
      'Intercity',
      'Car rental',
      'Courier',
    ]) {
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('Soon'), findsNWidgets(4));

    await tester.tap(find.text('To the airport'));
    await tester.pumpAndSettle();
    expect(find.text('Pickup'), findsNothing);

    await tester.tap(find.text('City rides'));
    await tester.pumpAndSettle();
    expect(find.text('Pickup'), findsOneWidget);
    expect(find.text('Destination'), findsOneWidget);
  });

  testWidgets('hub is localized to Russian', (tester) async {
    await tester.pumpWidget(
      _app(RidesHubScreen(api: RideApi(_Auth())), language: 'ru'),
    );
    expect(find.text('По городу'), findsOneWidget);
    expect(find.text('Межгород'), findsOneWidget);
    expect(find.text('Скоро'), findsNWidgets(4));
  });

  testWidgets('tariff cards show the server price only on the quoted class',
      (tester) async {
    await tester.pumpWidget(_app(RidesScreen(api: RideApi(_Auth()))));
    expect(find.text('Economy'), findsOneWidget);
    expect(find.text('Comfort'), findsOneWidget);
    expect(find.text('Business'), findsOneWidget);
    expect(find.textContaining('KZT'), findsNothing);

    await _pickBoth(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Get fare'));
    await tester.pumpAndSettle();
    expect(find.text('1200 KZT'), findsOneWidget);

    // Changing the class drops the quote: the price is never reused or guessed.
    await tester.tap(find.text('Comfort'));
    await tester.pumpAndSettle();
    expect(find.textContaining('KZT'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Get fare'), findsOneWidget);
  });

  testWidgets('searching state follows the real status and can be cancelled',
      (tester) async {
    final auth = _Auth();
    await tester.pumpWidget(_app(RidesScreen(api: RideApi(auth))));
    await _pickBoth(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Get fare'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Request ride'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Finding a driver...'), findsOneWidget);
    expect(find.text('Sending your request to drivers'), findsOneWidget);
    expect(find.text('Matching the nearest driver'), findsOneWidget);
    expect(find.text('Confirming the ride'), findsOneWidget);
    expect(find.text('Cancel ride'), findsOneWidget);
    expect(auth.calls, contains('POST rides/trip-1/dispatch'));
    // Dispatch returned SEARCHING_DRIVER: the first step is done, not faked as assigned.
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(find.text('Driver assigned'), findsNothing);

    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('a completed ride can be rated once and then closes',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final auth = _Auth(history: [_Auth.trip('COMPLETED', driver: true)]);
    await tester.pumpWidget(_app(RidesScreen(api: RideApi(auth))));
    await tester.tap(find.byTooltip('History'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ride complete'));
    await tester.pumpAndSettle();

    expect(find.text('Ride complete!'), findsOneWidget);
    expect(find.text('1200 KZT'), findsOneWidget);
    expect(find.text('Erlan'), findsOneWidget);
    expect(find.text('Hyundai Elantra · 774 AYA 02'), findsOneWidget);
    expect(find.byTooltip('Rating: 4 of 5'), findsOneWidget);

    await tester.tap(find.byTooltip('Rating: 4 of 5'));
    await tester.enterText(find.byType(TextField), '  Polite driver  ');
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();

    expect(auth.ratings, [
      {'stars': 4, 'comment': 'Polite driver'},
    ]);
    expect(find.text('Ride complete!'), findsNothing);
  });

  testWidgets(
      'closing without stars sends nothing; a stored rating is read-only',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final auth = _Auth(history: [_Auth.trip('COMPLETED', driver: true)]);
    await tester.pumpWidget(_app(RidesScreen(api: RideApi(auth))));
    await tester.tap(find.byTooltip('History'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ride complete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    expect(auth.ratings, isEmpty);

    final rated = _Auth(history: [
      {
        ..._Auth.trip('COMPLETED', driver: true),
        'rating': {'stars': 5, 'createdAt': '2026-11-22T11:00:00Z'}
      },
    ]);
    await tester.pumpWidget(const SizedBox());
    await tester
        .pumpWidget(_app(RidesScreen(api: RideApi(rated)), language: 'en'));
    await tester.tap(find.byTooltip('History'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ride complete'));
    await tester.pumpAndSettle();
    expect(find.text('Thanks for your rating'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });
}
