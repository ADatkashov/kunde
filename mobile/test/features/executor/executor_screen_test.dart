import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_mobile/core/localization/kunde_localizations.dart';
import 'package:kunde_mobile/features/executor/executor_screen.dart';
import 'package:kunde_mobile/features/identity/auth_repository.dart';

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
  testWidgets('Executor submits completion and reloads trip history',
      (tester) async {
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
