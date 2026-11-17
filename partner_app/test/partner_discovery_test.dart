import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_partner/data/partner_api.dart';

void main() {
  test('discovers only server-returned partner memberships', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/v1/partner/partners');
      expect(request.headers['Authorization'], 'Bearer test-token');
      return http.Response(
        '[{"id":"demo-1","name":"Демо","verificationStatus":"APPROVED"}]',
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = PartnerApi(
      baseUri: Uri.parse('https://example.test/api/v1/'),
      accessToken: () async => 'test-token',
      client: client,
    );
    final partners = await api.myPartners();
    expect(partners.single['id'], 'demo-1');
    api.close();
  });

  test('membership discovery preserves forbidden status', () async {
    final api = PartnerApi(
      baseUri: Uri.parse('https://example.test/api/v1/'),
      accessToken: () async => 'test-token',
      client: MockClient((_) async => http.Response('{}', 403)),
    );
    await expectLater(api.myPartners(),
      throwsA(isA<PartnerApiException>()
        .having((e) => e.statusCode, 'statusCode', 403)));
    api.close();
  });
}
