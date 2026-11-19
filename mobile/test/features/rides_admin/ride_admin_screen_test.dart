import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_mobile/core/localization/kunde_localizations.dart';
import 'package:kunde_mobile/features/identity/auth_repository.dart';
import 'package:kunde_mobile/features/rides_admin/ride_admin_screen.dart';

class _AdminSession implements AuthRepository {
  @override
  Future<dynamic> authorizedJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Set<int> expected = const {200},
    Map<String, String>? headers,
  }) async {
    expect((method, path), ('GET', 'admin/me/capabilities'));
    return <String, dynamic>{
      'permissions': ['DELIVERY_OPERATIONS'],
    };
  }

  @override
  Future<bool> logout() async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final width in [320.0, 390.0, 600.0, 840.0, 1280.0, 1920.0]) {
    testWidgets('shows authorized queues at width $width with 200% text', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          supportedLocales: KundeLocalizations.supportedLocales,
          localizationsDelegates: KundeLocalizations.localizationsDelegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: RideAdminScreen(auth: _AdminSession()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Couriers'), findsOneWidget);
      expect(find.text('Shipments'), findsOneWidget);
      expect(find.text('Delivery complaints'), findsOneWidget);
      expect(find.text('Drivers'), findsNothing);
      expect(find.text('Auto bookings'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
