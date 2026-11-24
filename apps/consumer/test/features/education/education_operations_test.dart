import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_operator/education_operations_screen.dart';
import 'package:kunde_auth/auth_repository.dart';

class _TeacherSession implements AuthRepository {
  String? attendance;

  @override
  Future<dynamic> authorizedJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Set<int> expected = const {200},
    Map<String, String>? headers,
  }) async {
    switch ((method, path)) {
      case ('GET', 'executor/education/sessions'):
        return [
          {'id': 'cohort', 'title': 'Python class', 'format': 'OFFLINE_GROUP'},
        ];
      case ('GET', 'executor/education/sessions/cohort/roster'):
        return [
          {'id': 'enrollment', 'attendance': attendance},
        ];
      case ('PUT', 'executor/education/sessions/cohort/roster/enrollment'):
        attendance = body!['status'] as String;
        return {'attendance': attendance};
      default:
        throw StateError('$method $path');
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('Executor opens a roster and sees saved attendance',
      (tester) async {
    final session = _TeacherSession();
    await tester.pumpWidget(
      MaterialApp(home: EducationOperationsScreen(auth: session)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open roster'));
    await tester.pumpAndSettle();
    expect(find.text('Attendance'), findsOneWidget);

    await tester.tap(find.text('Present'));
    await tester.pumpAndSettle();
    expect(session.attendance, 'PRESENT');
    expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Present'))
            .selected,
        isTrue);

    await tester.tap(find.byTooltip('Back to classes'));
    await tester.pumpAndSettle();
    expect(find.text('Python class'), findsOneWidget);
  });
}
