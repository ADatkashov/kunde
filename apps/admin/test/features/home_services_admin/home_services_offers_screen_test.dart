import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_admin/features/home_services_admin/home_services_offers_screen.dart';
import 'package:kunde_auth/auth_repository.dart';

class _Session implements AuthRepository {
  final calls = <String>[];
  Map<String, dynamic>? decision;

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
      decision = body;
      return {};
    }
    if (path.contains('offset=30')) return <Map<String, dynamic>>[];
    return path.contains('status=PENDING')
        ? [
            {
              'id': 'o1',
              'definitionCode': 'DEEP_CLEAN',
              'pricingModel': 'FROM',
              'venueName': 'Clean Co',
              'warrantyDays': 14,
              'status': 'PENDING',
              'version': 2,
            },
          ]
        : <Map<String, dynamic>>[];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('moderation actions mirror the backend state machine', () {
    final actions = HomeServicesOffersScreenState.actionsFor;
    expect(actions('PENDING'), ['APPROVE', 'REJECT']);
    expect(actions('PUBLISHED'), ['SUSPEND']);
    expect(actions('SUSPENDED'), ['RESTORE']);
    expect(actions('DRAFT'), isEmpty);
  });

  testWidgets('approve needs a reason, sends expectedVersion and reloads', (
    tester,
  ) async {
    final auth = _Session();
    await tester.pumpWidget(
      MaterialApp(home: HomeServicesOffersScreen(auth: auth)),
    );
    await tester.pumpAndSettle();
    expect(find.text('DEEP_CLEAN · FROM'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('approve-o1')));
    await tester.pumpAndSettle();
    final confirm = find.byKey(const ValueKey('confirm'));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.enterText(find.byKey(const ValueKey('reason')), 'checked');
    await tester.pump();
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(auth.decision, {
      'action': 'APPROVE',
      'expectedVersion': 2,
      'reason': 'checked',
    });
    expect(
      auth.calls.where((c) =>
          c ==
          'GET admin/home-services/offers?status=PENDING&limit=30&offset=0'),
      hasLength(2),
    );
  });
}
