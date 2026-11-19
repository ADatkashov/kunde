import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_mobile/core/localization/kunde_localizations.dart';
import 'package:kunde_mobile/features/admin_employees/admin_employee_screen.dart';
import 'package:kunde_mobile/features/identity/auth_repository.dart';

class _Session implements AuthRepository {
  final paths = <String>[];

  @override
  Future<dynamic> authorizedJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Set<int> expected = const {200},
    Map<String, String>? headers,
  }) async {
    expect(method, 'GET');
    paths.add(path);
    final first = path == 'admin/employees';
    return <String, dynamic>{
      'employees': [
        <String, dynamic>{
          'id': first ? 'employee-a' : 'employee-b',
          'displayName': first ? 'Employee A' : 'Employee B',
          'hasAccess': first,
        },
      ],
      'next': first ? 'employee-a' : null,
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('pages employee access status with large text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = _Session();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: KundeLocalizations.supportedLocales,
      localizationsDelegates: KundeLocalizations.localizationsDelegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: AdminEmployeeScreen(auth: session),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Access active'), findsOneWidget);
    await tester.tap(find.text('Next page'));
    await tester.pumpAndSettle();
    expect(find.text('Employee B'), findsOneWidget);
    expect(find.text('Access inactive'), findsOneWidget);
    expect(
        session.paths, ['admin/employees', 'admin/employees?after=employee-a']);
    expect(tester.takeException(), isNull);
  });
}
