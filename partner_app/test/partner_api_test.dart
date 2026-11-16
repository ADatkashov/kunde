import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_partner/data/partner_api.dart';
import 'package:kunde_partner/data/partner_operations.dart';

void main() {
  test('missing token fails closed without network access', () async {
    var called = false;
    final api = PartnerApi(
      baseUri: Uri.parse('https://example.test/api/v1/'),
      accessToken: () async => null,
      client: MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      }),
    );
    await expectLater(api.get('partner/partners/p1/food/orders'),
        throwsA(isA<PartnerApiException>()));
    expect(called, isFalse);
    api.close();
  });

  test('partner order request carries bearer token and scoped URL', () async {
    final api = PartnerApi(
      baseUri: Uri.parse('https://example.test/api/v1/'),
      accessToken: () async => 'test-token',
      client: MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer test-token');
        expect(request.url.path, '/api/v1/partner/partners/p1/food/orders');
        expect(request.url.queryParameters['scope'], 'active');
        return http.Response(jsonEncode({'items': []}), 200,
            headers: {'content-type': 'application/json'});
      }),
    );
    expect((await PartnerOperations(api, 'p1').activeOrders())['items'], isEmpty);
    api.close();
  });

  test('order transition uses POST JSON with partner scope', () async {
    final api = PartnerApi(
      baseUri: Uri.parse('https://example.test/api/v1/'),
      accessToken: () async => 'test-token',
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path,
            '/api/v1/partner/partners/p1/food/orders/o1/status');
        expect(jsonDecode(request.body),
            {'status': 'CANCELLED', 'reason': 'Out of stock'});
        return http.Response('{"status":"CANCELLED"}', 200);
      }),
    );
    final result = await PartnerOperations(api, 'p1')
        .updateOrder('o1', 'CANCELLED', reason: 'Out of stock');
    expect(result['status'], 'CANCELLED');
    api.close();
  });

  test('server denies other partner and client preserves error', () async {
    final api = PartnerApi(
      baseUri: Uri.parse('https://example.test/api/v1/'),
      accessToken: () async => 'test-token',
      client: MockClient((_) async => http.Response('{"code":"PARTNER_NOT_FOUND"}', 404)),
    );
    await expectLater(
      PartnerOperations(api, 'other').activeOrders(),
      throwsA(isA<PartnerApiException>()
          .having((e) => e.statusCode, 'statusCode', 404)),
    );
    api.close();
  });
}
