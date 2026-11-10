import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_mobile/features/home/data/kunde_api.dart';
import 'package:kunde_mobile/features/home/data/platform_snapshot.dart';

void main() {
  group('KundeApi', () {
    test('loads only server-reported foundation capabilities', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/v1/capabilities');
        return http.Response(
          jsonEncode({
            'releaseStage': 'FOUNDATION',
            'marketplaceEnabled': false,
            'oidcIssuerConfigured': false,
            'aiEnabled': false,
          }),
          200,
        );
      });
      final api = KundeApi(
          baseUri: Uri.parse('https://api.example.test/api/v1'),
          client: client);

      final result = await api.loadPlatformSnapshot();

      expect(result, isA<PlatformSnapshot>());
      expect(result.marketplaceEnabled, isFalse);
      expect(result.oidcIssuerConfigured, isFalse);
      expect(result.aiEnabled, isFalse);
      api.close();
    });

    test('does not expose API response details as a user-facing exception',
        () async {
      final client = MockClient((_) async =>
          http.Response('internal database host: db.internal', 500));
      final api = KundeApi(
          baseUri: Uri.parse('https://api.example.test/api/v1/'),
          client: client);

      await expectLater(
        api.loadPlatformSnapshot(),
        throwsA(isA<KundeApiException>().having(
          (error) => error.kind,
          'failure kind',
          KundeApiFailure.unavailable,
        )),
      );
      api.close();
    });

    test('rejects malformed capability responses', () async {
      final client = MockClient(
          (_) async => http.Response('{"marketplaceEnabled": "yes"}', 200));
      final api = KundeApi(
          baseUri: Uri.parse('https://api.example.test/api/v1/'),
          client: client);

      await expectLater(
        api.loadPlatformSnapshot(),
        throwsA(isA<KundeApiException>().having(
          (error) => error.kind,
          'failure kind',
          KundeApiFailure.unexpectedResponse,
        )),
      );
      api.close();
    });
  });
}
