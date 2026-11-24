import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_admin/features/home_services_admin/home_services_categories_screen.dart';
import 'package:kunde_auth/auth_repository.dart';

class _Session implements AuthRepository {
  Map<String, dynamic>? saved;
  int reads = 0;

  @override
  Future<dynamic> authorizedJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Set<int> expected = const {200},
    Map<String, String>? headers,
  }) async {
    if (method == 'PUT') {
      expect(path, 'admin/home-services/categories/CLEANING');
      saved = body;
      return {};
    }
    expect(path, 'admin/home-services/categories?limit=20&offset=0');
    reads++;
    return [
      {
        'code': 'CLEANING',
        'nameRu': 'Уборка',
        'nameKk': 'Үй жинау',
        'nameEn': 'Cleaning',
        'icon': 'cleaning_services',
        'active': true,
        'sortOrder': 10,
        'version': 3,
      },
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('editor validates and sends a versioned change then reloads', (
    tester,
  ) async {
    final auth = _Session();
    await tester.pumpWidget(
      MaterialApp(home: HomeServicesCategoriesScreen(auth: auth)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cleaning'));
    await tester.pumpAndSettle();

    final reason = find.byKey(const ValueKey('reason'));
    final save = find.widgetWithText(FilledButton, 'Save');
    final editorScroll = find.descendant(
      of: find.byType(Form),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    );
    await tester.scrollUntilVisible(save, 120, scrollable: editorScroll);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(auth.saved, isNull);
    expect(find.text('Check this value'), findsOneWidget);

    await tester.ensureVisible(reason);
    await tester.enterText(reason, 'Verify display settings');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(auth.saved?['reason'], 'Verify display settings');
    expect(auth.saved?['expectedVersion'], 3);
    expect(auth.saved?['sortOrder'], 10);
    expect(auth.reads, 2);
    expect(find.text('Cleaning'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
