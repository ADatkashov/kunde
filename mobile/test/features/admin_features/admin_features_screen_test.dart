import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_mobile/core/localization/kunde_localizations.dart';
import 'package:kunde_mobile/features/admin_features/admin_features_screen.dart';
import 'package:kunde_mobile/features/identity/auth_repository.dart';

class _Session implements AuthRepository {
  bool autoOn = true;
  int version = 0;
  String? reason;
  final puts = <Map<String, dynamic>>[];
  bool conflictNext = false;

  List<Map<String, dynamic>> get _rows => [
        {
          'feature': 'AUTO',
          'allowedByEnvironment': true,
          'enabled': autoOn,
          'effective': autoOn,
          'version': version,
          'reason': reason
        },
        {
          'feature': 'RIDES',
          'allowedByEnvironment': false,
          'enabled': true,
          'effective': false,
          'version': 0
        },
      ];

  @override
  Future<dynamic> authorizedJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Set<int> expected = const {200},
    Map<String, String>? headers,
  }) async {
    if (method == 'GET') return _rows;
    expect(path, 'admin/features/AUTO');
    puts.add(body!);
    if (conflictNext) {
      conflictNext = false;
      throw IdentityApiError(409, 'VERSION_CONFLICT');
    }
    autoOn = body['enabled'] as bool;
    version += 1;
    reason = body['reason'] as String;
    return _rows.first;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(AuthRepository auth) => MaterialApp(
      locale: const Locale('en'),
      supportedLocales: KundeLocalizations.supportedLocales,
      localizationsDelegates: KundeLocalizations.localizationsDelegates,
      home: AdminFeaturesScreen(auth: auth),
    );

void main() {
  testWidgets(
      'switching a feature needs a reason, sends the version and shows the journaled reason',
      (tester) async {
    tester.view.physicalSize = const Size(480, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = _Session();
    await tester.pumpWidget(_app(session));
    await tester.pumpAndSettle();

    // the environment is the ceiling: Rides cannot be switched here
    expect(
        find.textContaining('Not allowed by the environment'), findsOneWidget);
    final rides = tester
        .widget<SwitchListTile>(find.byKey(const ValueKey('feature-RIDES')));
    expect(rides.onChanged, isNull);

    await tester.tap(find.byKey(const ValueKey('feature-AUTO')));
    await tester.pumpAndSettle();
    expect(find.text('Auto: turn off'), findsOneWidget);
    var apply = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(apply.onPressed, isNull, reason: 'a reason is mandatory');
    await tester.enterText(find.byType(TextField), 'maintenance window');
    await tester.pump();
    apply = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(apply.onPressed, isNotNull);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(session.puts.single,
        {'enabled': false, 'reason': 'maintenance window'});
    expect(
        find.text(
            'Switched off by an administrator\nReason: maintenance window'),
        findsOneWidget);
    expect(tester.takeException(), isNull);

    // switching back sends the version that was read
    await tester.tap(find.byKey(const ValueKey('feature-AUTO')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'work finished');
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(session.puts.last,
        {'enabled': true, 'reason': 'work finished', 'version': 1});
  });

  testWidgets('a version conflict explains itself and reloads the list',
      (tester) async {
    tester.view.physicalSize = const Size(480, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = _Session()..conflictNext = true;
    await tester.pumpWidget(_app(session));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('feature-AUTO')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'try it');
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.textContaining('changed by someone else'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
