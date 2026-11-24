import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_partner/data/partner_api.dart';

import 'support/fake_backend.dart';

PartnerApi api(http.Client c,
        {Future<String?> Function()? refresh, int retries = 2}) =>
    PartnerApi(
      baseUri: apiBase,
      accessToken: () async => 'tok',
      forceRefresh: refresh,
      client: c,
      retryDelay: Duration.zero,
      getRetries: retries,
      timeout: const Duration(milliseconds: 200),
    );

void main() {
  test('sends bearer token and decodes UTF-8 even without a charset header',
      () async {
    final backend = FakeBackend();
    final list = await api(backend.client).getList('partner/partners');
    expect(list.single['displayName'], 'Демо-партнёр');
    expect(backend.headers.single['Authorization'], 'Bearer tok');
  });

  test('normalizes nothing: arrays stay arrays, maps stay maps', () async {
    final client = MockClient((_) async => http.Response('{"a":1}', 200));
    expect(await api(client).getMap('x'), {'a': 1});
    await expectLater(api(client).getList('x'), throwsFormatException);
  });

  test('extracts the backend error code', () async {
    final client = MockClient((_) async => http.Response(
        '{"status":409,"code":"ORDER_TRANSITION_INVALID","message":"no"}',
        409));
    await expectLater(
      api(client).postMap('x', {}),
      throwsA(isA<PartnerApiException>()
          .having((e) => e.code, 'code', 'ORDER_TRANSITION_INVALID')
          .having((e) => e.kind, 'kind', ApiErrorKind.conflict)),
    );
  });

  test('maps 401/403/404/5xx to kinds and detects revoked access', () async {
    Future<PartnerApiException> fail(int status, [String body = '{}']) async {
      final client = MockClient((_) async => http.Response(body, status));
      try {
        await api(client, retries: 0).getMap('x');
      } on PartnerApiException catch (e) {
        return e;
      }
      throw StateError('no failure');
    }

    expect((await fail(401)).kind, ApiErrorKind.unauthorized);
    expect((await fail(403)).kind, ApiErrorKind.forbidden);
    expect((await fail(404, '{"code":"PARTNER_NOT_FOUND"}')).isAccessRevoked,
        isTrue);
    expect((await fail(500)).kind, ApiErrorKind.server);
    expect((await fail(400)).kind, ApiErrorKind.validation);
  });

  test('a 401 refreshes the token once and replays the request', () async {
    var calls = 0;
    final seen = <String?>[];
    final client = MockClient((r) async {
      calls++;
      seen.add(r.headers['Authorization']);
      return calls == 1
          ? http.Response('{}', 401)
          : http.Response('{"ok":true}', 200);
    });
    final a = PartnerApi(
      baseUri: apiBase,
      accessToken: () async => 'old',
      forceRefresh: () async => 'new',
      client: client,
    );
    expect(await a.getMap('x'), {'ok': true});
    expect(calls, 2);
  });

  test('preserves the shipment idempotency key across an auth refresh',
      () async {
    const key = 'synthetic-shipment-request-1';
    final seen = <String?>[];
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      seen.add(request.headers['Idempotency-Key']);
      return seen.length == 1
          ? http.Response('{}', 401)
          : http.Response('{"id":"shipment"}', 201);
    });
    final result = await api(client, refresh: () async => 'new').postMap(
        'partner/partners/test/deliveries', {'quoteId': 'quote'},
        idempotencyKey: key);
    expect(result['id'], 'shipment');
    expect(seen, [key, key]);
  });

  test('a persistent 401 is not replayed forever', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response('{}', 401);
    });
    final a = api(client, refresh: () async => 'new');
    await expectLater(a.getMap('x'), throwsA(isA<PartnerApiException>()));
    expect(calls, 2);
  });

  test('GET is retried on connectivity failure and 503, then succeeds',
      () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      if (calls == 1) throw const SocketException('down');
      if (calls == 2) return http.Response('{}', 503);
      return http.Response('{"ok":1}', 200);
    });
    expect(await api(client).getMap('x'), {'ok': 1});
    expect(calls, 3);
  });

  test('POST is never retried, so an action cannot be duplicated', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      throw const SocketException('down');
    });
    await expectLater(
      api(client).postMap('x', {'a': 1}),
      throwsA(isA<PartnerApiException>()
          .having((e) => e.kind, 'kind', ApiErrorKind.network)),
    );
    expect(calls, 1);
  });

  test('a hanging server becomes a timeout error', () async {
    final client = MockClient((_) => Completer<http.Response>().future);
    await expectLater(
      api(client, retries: 0).getMap('x'),
      throwsA(isA<PartnerApiException>()
          .having((e) => e.kind, 'kind', ApiErrorKind.timeout)),
    );
  });

  test('a timeout is not retried (slow server, not an unreachable one)',
      () async {
    var calls = 0;
    final client = MockClient((_) {
      calls++;
      return Completer<http.Response>().future;
    });
    await expectLater(
      api(client).getMap('x'),
      throwsA(isA<PartnerApiException>()
          .having((e) => e.kind, 'kind', ApiErrorKind.timeout)),
    );
    expect(calls, 1);
  });

  test('missing token fails before any request is sent', () async {
    var calls = 0;
    final a = PartnerApi(
      baseUri: apiBase,
      accessToken: () async => null,
      client: MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    await expectLater(a.getMap('x'), throwsA(isA<PartnerApiException>()));
    expect(calls, 0);
  });
}
