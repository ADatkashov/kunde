import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_mobile/core/localization/kunde_localizations.dart';
import 'package:kunde_mobile/features/education/education_screen.dart';
import 'package:kunde_mobile/features/home/data/kunde_api.dart';
import 'package:kunde_mobile/features/home/data/platform_snapshot.dart';

void main() {
  test('education capability defaults to off for older backends', () {
    final json = <String, dynamic>{
      'releaseStage': 'FOUNDATION',
      'marketplaceEnabled': false,
      'oidcIssuerConfigured': false,
      'aiEnabled': false,
    };
    expect(PlatformSnapshot.fromJson(json).educationEnabled, isFalse);
    json['educationEnabled'] = true;
    expect(PlatformSnapshot.fromJson(json).educationEnabled, isTrue);
  });

  testWidgets('searches API and opens the returned curriculum', (tester) async {
    final requests = <Uri>[];
    final course = {
      'id': 'python',
      'title': 'Python для начинающих',
      'organization': 'Тестовая студия',
      'priceMinor': 100000,
      'synthetic': true,
    };
    final api = KundeApi(
      baseUri: Uri.parse('https://api.example.test/api/v1/'),
      client: MockClient((request) async {
        requests.add(request.url);
        final body = request.url.path.endsWith('/python')
            ? {
                'course': course,
                'description': 'Введение в Python',
                'formats': [],
                'modules': [
                  {
                    'title': 'Основы Python',
                    'lessons': [
                      {'title': 'Переменные'},
                    ],
                  },
                ],
              }
            : {
                'items': [course],
                'hasMore': false,
              };
        return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
      }),
    );
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('kk'),
        localizationsDelegates: KundeLocalizations.localizationsDelegates,
        supportedLocales: KundeLocalizations.supportedLocales,
        home: EducationScreen(api: api),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), ' Python ');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(requests.last.queryParameters['q'], 'Python');
    await tester.ensureVisible(find.widgetWithText(FilterChip, 'IT'));
    await tester.tap(find.widgetWithText(FilterChip, 'IT'));
    await tester.pumpAndSettle();
    expect(requests.last.queryParameters['category'], 'IT');
    expect(requests.last.queryParameters['q'], 'Python');
    expect(find.text('Курс немесе мектеп'), findsOneWidget);
    final title = find.text('Python для начинающих');
    await tester.ensureVisible(title);
    await tester.tap(title);
    await tester.pumpAndSettle();
    expect(requests.last.path, '/api/v1/education/courses/python');
    await tester.tap(find.text('Основы Python'));
    await tester.pumpAndSettle();
    expect(find.text('Переменные'), findsOneWidget);
  });

  testWidgets('catalog fits small screens in RU, KK and EN at 200% text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = KundeApi(
      baseUri: Uri.parse('https://api.example.test/api/v1/'),
      client: MockClient((request) async =>
          http.Response('{"items":[],"hasMore":false}', 200)),
    );
    addTearDown(api.close);
    for (final locale in const [Locale('ru'), Locale('kk'), Locale('en')]) {
      for (final theme in [ThemeData.light(), ThemeData.dark()]) {
        await tester.pumpWidget(MaterialApp(
          locale: locale,
          localizationsDelegates: KundeLocalizations.localizationsDelegates,
          supportedLocales: KundeLocalizations.supportedLocales,
          theme: theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: EducationScreen(api: api),
        ));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byType(FilterChip).last,
          120,
          scrollable: find.descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          ).first,
        );
        expect(tester.takeException(), isNull);
      }
    }
  });
}
