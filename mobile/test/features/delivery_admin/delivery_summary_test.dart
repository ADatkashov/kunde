import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_mobile/core/localization/kunde_localizations.dart';
import 'package:kunde_mobile/features/delivery_admin/delivery_admin_screen.dart';
import 'package:kunde_mobile/features/identity/auth_repository.dart';

class _Session implements AuthRepository {
  final periods = <Duration>[];
  final shipmentQueries = <Map<String, String>>[];

  @override
  Future<dynamic> authorizedJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Set<int> expected = const {200},
    Map<String, String>? headers,
  }) async {
    expect(method, 'GET');
    final uri = Uri.parse(path);
    if (uri.path == 'admin/deliveries') {
      shipmentQueries.add(uri.queryParameters);
      return <Map<String, dynamic>>[];
    }
    expect(uri.path, 'admin/deliveries/summary');
    final from = DateTime.parse(uri.queryParameters['from']!);
    final to = DateTime.parse(uri.queryParameters['to']!);
    periods.add(to.difference(from));
    return <String, dynamic>{
      'total': 3,
      'byStatus': [
        {'status': 'RETURNED_TO_SENDER', 'shipments': 3},
      ],
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('shipment list sends status and date filters together',
      (tester) async {
    final session = _Session();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: KundeLocalizations.supportedLocales,
      localizationsDelegates: KundeLocalizations.localizationsDelegates,
      home:
          DeliveryAdminScreen(auth: session, area: DeliveryAdminArea.shipments),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Filter by status'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Created'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Filter by date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Last 24 hours'));
    await tester.pumpAndSettle();

    expect(session.shipmentQueries.first, isEmpty);
    expect(session.shipmentQueries[1], {'status': 'CREATED'});
    final filtered = session.shipmentQueries.last;
    expect(filtered['status'], 'CREATED');
    expect(
        DateTime.parse(filtered['to']!)
            .difference(DateTime.parse(filtered['from']!)),
        const Duration(days: 1));
  });

  testWidgets('Delivery summary requests server totals for the selected period',
      (tester) async {
    final session = _Session();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: KundeLocalizations.supportedLocales,
      localizationsDelegates: KundeLocalizations.localizationsDelegates,
      home:
          DeliveryAdminScreen(auth: session, area: DeliveryAdminArea.shipments),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Summary'));
    await tester.pumpAndSettle();
    expect(find.text('Total shipments · 3'), findsOneWidget);
    expect(find.text('Returned · 3'), findsOneWidget);
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Last 24 hours').last);
    await tester.pumpAndSettle();
    expect(session.periods, [const Duration(days: 7), const Duration(days: 1)]);
  });
}
