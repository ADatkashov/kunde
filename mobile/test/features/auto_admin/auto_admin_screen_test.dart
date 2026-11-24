import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_localization/kunde_localizations.dart';
import 'package:kunde_mobile/features/auto_admin/auto_admin_screen.dart';
import 'package:kunde_auth/auth_repository.dart';

/// Records every call; answers like the admin Auto API.
class _AdminSession implements AuthRepository {
  final calls = <String>[];
  final bodies = <Map<String, dynamic>?>[];
  bool resolved = false;

  @override
  Future<dynamic> authorizedJson(String method, String path,
      {Map<String, dynamic>? body,
      Set<int> expected = const {200},
      Map<String, String>? headers}) async {
    calls.add('$method $path');
    bodies.add(body);
    switch ((method, path)) {
      case ('GET', 'admin/auto/categories'):
        return [
          {
            'code': 'CAR_WASH',
            'nameRu': 'Автомойка',
            'enabled': true,
            'mobile': false
          },
          {
            'code': 'ROADSIDE',
            'nameRu': 'Выездная помощь',
            'enabled': true,
            'mobile': true
          },
        ];
      case ('PATCH', 'admin/auto/categories/CAR_WASH'):
        return {
          'code': 'CAR_WASH',
          'nameRu': 'Автомойка',
          'enabled': body!['enabled'],
          'mobile': false
        };
      case ('GET', 'admin/auto/specialists?includeReviewed=true'):
        return [
          {
            'userId': 'u-1',
            'name': 'Тест Специалист',
            'status': 'PENDING',
            'online': false,
            'categories': []
          },
          {
            'userId': 'u-2',
            'name': 'Другой',
            'status': 'APPROVED',
            'online': true,
            'categories': ['ROADSIDE']
          },
        ];
      case ('POST', 'admin/auto/specialists/u-1/decision'):
        return {
          'userId': 'u-1',
          'status': body!['approve'] == true ? 'APPROVED' : 'BLOCKED'
        };
      case ('GET', 'admin/auto/complaints?includeResolved=true'):
        return [
          {
            'id': 'c-1',
            'kind': 'QUALITY',
            'description': 'Масло долили не то',
            'status': resolved ? 'RESOLVED' : 'OPEN',
            'resolution': resolved ? 'Решено' : null
          },
        ];
      case ('POST', 'admin/auto/complaints/c-1/resolve'):
        resolved = true;
        return {'id': 'c-1', 'status': 'RESOLVED'};
      case ('GET', 'admin/auto/venues'):
        return [
          {'id': 'v-1', 'name': 'Тестовое СТО', 'open': true},
        ];
      case ('PATCH', 'admin/auto/venues/v-1'):
        return {'id': 'v-1', 'name': 'Тестовое СТО', 'open': body!['open']};
      case ('GET', 'admin/auto/bookings'):
        return [
          {
            'id': 'b-1',
            'venueName': 'Тестовое СТО',
            'serviceName': 'Замена масла',
            'status': 'CONFIRMED',
            'priceMinor': 1200000,
            'priceKind': 'FROM'
          },
        ];
    }
    throw StateError('Unexpected API call $method $path');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(AuthRepository auth, AutoAdminArea area) => MaterialApp(
      locale: const Locale('ru'),
      supportedLocales: KundeLocalizations.supportedLocales,
      localizationsDelegates: KundeLocalizations.localizationsDelegates,
      home: AutoAdminScreen(
          key: ValueKey('${auth.hashCode}-$area'), auth: auth, area: area),
    );

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(900, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

void main() {
  testWidgets('category switch sends the enabled flag to the admin API',
      (tester) async {
    _tall(tester);
    final s = _AdminSession();
    await tester.pumpWidget(_app(s, AutoAdminArea.categories));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Автомойка'));
    await tester.pumpAndSettle();
    expect(s.calls, contains('PATCH admin/auto/categories/CAR_WASH'));
    expect(s.bodies[s.calls.indexOf('PATCH admin/auto/categories/CAR_WASH')],
        {'enabled': false});
  });

  testWidgets(
      'approving a specialist needs a category and a basis, then sends both',
      (tester) async {
    _tall(tester);
    final s = _AdminSession();
    await tester.pumpWidget(_app(s, AutoAdminArea.specialists));
    await tester.pumpAndSettle();
    expect(find.text('Тест Специалист'), findsOneWidget);
    await tester.tap(find.text('Одобрить'));
    await tester.pumpAndSettle();
    // only the on-site category is offered
    expect(find.text('Выездная помощь'), findsOneWidget);
    expect(find.text('Автомойка'), findsNothing);
    final confirm = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Одобрить'));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.tap(find.text('Выездная помощь'));
    await tester.enterText(find.byType(TextField), 'Документы проверены');
    await tester.pump();
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    final i = s.calls.indexOf('POST admin/auto/specialists/u-1/decision');
    expect(i, greaterThan(-1));
    expect(s.bodies[i], {
      'approve': true,
      'categories': ['ROADSIDE'],
      'reason': 'Документы проверены'
    });
  });

  testWidgets(
      'a complaint is resolved with a written resolution and then shown as resolved',
      (tester) async {
    _tall(tester);
    final s = _AdminSession();
    await tester.pumpWidget(_app(s, AutoAdminArea.complaints));
    await tester.pumpAndSettle();
    expect(find.textContaining('Масло долили не то'), findsOneWidget);
    await tester.tap(find.text('Закрыть жалобу'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Подтвердить'))
            .onPressed,
        isNull);
    await tester.enterText(find.byType(TextField), 'Решено');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Подтвердить'));
    await tester.pumpAndSettle();
    expect(s.bodies[s.calls.indexOf('POST admin/auto/complaints/c-1/resolve')],
        {'resolution': 'Решено'});
    expect(find.text('Закрыть жалобу'), findsNothing);
  });

  testWidgets('blocking a venue and viewing bookings use only server data',
      (tester) async {
    _tall(tester);
    final s = _AdminSession();
    await tester.pumpWidget(_app(s, AutoAdminArea.venues));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Тестовое СТО'));
    await tester.pumpAndSettle();
    expect(s.bodies[s.calls.indexOf('PATCH admin/auto/venues/v-1')],
        {'open': false});
    final s2 = _AdminSession();
    await tester.pumpWidget(_app(s2, AutoAdminArea.bookings));
    await tester.pumpAndSettle();
    expect(find.textContaining('Замена масла'), findsOneWidget);
    expect(find.textContaining('Подтверждена'), findsOneWidget);
  });

  testWidgets('an API failure shows the retry state', (tester) async {
    _tall(tester);
    final broken = _Broken();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ru'),
      supportedLocales: KundeLocalizations.supportedLocales,
      localizationsDelegates: KundeLocalizations.localizationsDelegates,
      home: AutoAdminScreen(auth: broken, area: AutoAdminArea.venues),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Повторить'), findsOneWidget);
  });
}

class _Broken implements AuthRepository {
  @override
  Future<dynamic> authorizedJson(String method, String path,
          {Map<String, dynamic>? body,
          Set<int> expected = const {200},
          Map<String, String>? headers}) =>
      throw IdentityApiError(500, 'X');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
