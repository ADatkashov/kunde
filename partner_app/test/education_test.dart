import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_partner/data/partner_api.dart';
import 'package:kunde_partner/data/partner_operations.dart';
import 'package:kunde_partner/features/education/partner_education_screen.dart';

void main() {
  testWidgets('Partner saves a course with a quiz and reloads the catalog',
      (tester) async {
    Map<String, dynamic>? submitted;
    final draft = {
      'id': 'course',
      'title': 'Course with quiz',
      'status': 'DRAFT',
      'format': 'ONLINE_RECORDED',
    };
    final api = PartnerApi(
      baseUri: Uri.parse('https://api.example.test/api/v1/'),
      accessToken: () async => 'synthetic',
      client: MockClient((request) async {
        expect(request.url.path,
            '/api/v1/partner/partners/owner/education/courses');
        if (request.method == 'POST') {
          submitted = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode(draft), 201);
        }
        return http.Response(jsonEncode(submitted == null ? [] : [draft]), 200);
      }),
    );
    await tester.pumpWidget(MaterialApp(
      home: PartnerEducationScreen(
        ops: PartnerOperations(api, 'owner'),
        canManage: true,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create synthetic course'));
    await tester.pumpAndSettle();
    Future<void> enter(String label, String value) async {
      final field = find.byWidgetPredicate((widget) =>
          widget is TextField && widget.decoration?.labelText == label);
      await tester.ensureVisible(field);
      await tester.enterText(field, value);
    }

    await enter('Title', 'Course with quiz');
    await enter('Description', 'A synthetic lesson on loops');
    await enter('Category code', 'IT');
    await enter('City', 'Almaty');
    await enter('Language code', 'en');
    await enter('Price in tiyn', '1000');
    await enter('Duration (min)', '45');
    await enter('Lesson text', 'Use a loop to repeat a statement');

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final quizSwitch = find.byType(Switch);
    await tester.ensureVisible(quizSwitch);
    await tester.pumpAndSettle();
    await tester.tap(quizSwitch);
    await tester.pumpAndSettle();
    await enter('Question', 'What repeats?');
    await enter('Answer A', 'A loop');
    await enter('Answer B', 'A number');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(submitted?['quiz'], {
      'question': 'What repeats?',
      'choices': ['A loop', 'A number'],
      'correctChoice': 0,
      'maxAttempts': 3,
    });
    expect(find.text('Course with quiz'), findsOneWidget);
  });
}
