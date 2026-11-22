import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_partner/data/partner_api.dart';
import 'package:kunde_partner/data/partner_operations.dart';
import 'package:kunde_partner/features/delivery/business_delivery_screen.dart';

void main() {
  testWidgets('business shipment creation follows the server capabilities',
      (tester) async {
    final api = PartnerApi(
      baseUri: Uri.parse('https://api.example.test/api/v1/'),
      accessToken: () async => 'fixture-token',
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path,
            startsWith('/api/v1/partner/partners/p1/deliveries'));
        return http.Response('[]', 200);
      }),
    );
    final ops = PartnerOperations(api, 'p1');

    for (final (maps, synthetic) in [
      (false, false),
      (false, true),
      (true, false)
    ]) {
      await tester.pumpWidget(MaterialApp(
        key: ValueKey((maps, synthetic)),
        home: BusinessDeliveryScreen(
          ops: ops,
          synthetic: synthetic,
          mapsEnabled: maps,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('New test shipment'),
          synthetic ? findsOneWidget : findsNothing);
      expect(
          find.text('Create shipment'), maps ? findsOneWidget : findsNothing);
      if (maps) {
        await tester.tap(find.text('Create shipment'));
        await tester.pumpAndSettle();
        expect(find.text('Choose on KUNDE Maps'), findsNWidgets(2));
      }
    }
  });
}
