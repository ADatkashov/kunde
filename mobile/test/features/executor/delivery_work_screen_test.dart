import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_mobile/core/localization/kunde_localizations.dart';
import 'package:kunde_mobile/features/executor/delivery_work_screen.dart';
import 'package:kunde_mobile/features/identity/auth_repository.dart';

class _CourierSession implements AuthRepository {
  bool handedOff = false;

  @override
  Future<dynamic> authorizedJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Set<int> expected = const {200},
    Map<String, String>? headers,
  }) async {
    return switch ((method, path)) {
      ('GET', 'executor/deliveries/profile') => {
          'name': 'Test courier',
          'status': 'APPROVED',
          'online': false,
        },
      ('GET', 'executor/deliveries') => [
          {
            'id': 'shipment',
            'status': handedOff ? 'DELIVERED' : 'IN_TRANSIT',
            'parcelType': 'DOCUMENTS',
            'syntheticRoute': true,
          }
        ],
      ('POST', 'executor/deliveries/shipment/handoff') =>
        _verify(body, expected),
      _ => throw StateError('Unexpected API call'),
    };
  }

  Null _verify(Map<String, dynamic>? body, Set<int> expected) {
    expect(body, {'code': '01234567'});
    expect(expected, {204});
    handedOff = true;
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('confirms a handoff through the assigned courier API',
      (tester) async {
    final session = _CourierSession();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: KundeLocalizations.supportedLocales,
      localizationsDelegates: KundeLocalizations.localizationsDelegates,
      home: DeliveryWorkScreen(auth: session, synthetic: true),
    ));
    await tester.pumpAndSettle();
    expect(find.text('In transit'), findsOneWidget);
    expect(find.text('Complete delivery'), findsNothing);
    await tester.tap(find.text('Confirm handoff'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '01234567');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verify code'));
    await tester.pumpAndSettle();
    expect(find.text('Handoff confirmed'), findsOneWidget);
    expect(find.text('Complete delivery'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
