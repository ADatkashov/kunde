import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_partner/auth/partner_session.dart';

import 'support/fake_backend.dart';

PartnerSession session(FakeBackend b, MemoryStore store, {Uri? base}) =>
    PartnerSession(apiBase: base ?? apiBase, client: b.client, storage: store);

void main() {
  test('rejects an insecure API base before sending anything', () async {
    final b = FakeBackend();
    final s = session(b, MemoryStore(),
        base: Uri.parse('http://example.test/api/v1/'));
    await expectLater(
        s.requestOtp('+77000000002'),
        throwsA(isA<PartnerAuthException>()
            .having((e) => e.code, 'code', 'INVALID_API_BASE')));
    expect(b.calls, isEmpty);
  });

  test('an empty (unconfigured) API base is invalid', () {
    final s = PartnerSession(apiBase: Uri.parse(''), storage: MemoryStore());
    expect(s.baseIsValid, isFalse);
  });

  test('verifyOtp stores only the refresh token; access token stays in memory',
      () async {
    final b = FakeBackend();
    final store = MemoryStore();
    final s = session(b, store);
    await s.verifyOtp('+77000000002', '123456');
    final raw = store.data['kunde.partner.session.v1']!;
    expect(raw, contains('refresh-v'));
    expect(raw, isNot(contains('access-v')));
    expect(await s.accessToken(), 'access-v');
    expect(b.refreshCount, 0, reason: 'fresh access token is reused');
  });

  test('a wrong code is reported as WRONG_CODE and stores nothing', () async {
    final store = MemoryStore();
    final s = session(FakeBackend(), store);
    await expectLater(
        s.verifyOtp('+77000000002', '000000'),
        throwsA(isA<PartnerAuthException>()
            .having((e) => e.code, 'code', PartnerAuthException.wrongCode)));
    expect(store.data, isEmpty);
  });

  test('rate limiting (429) is distinguishable from a wrong code', () async {
    final b = FakeBackend()
      ..overrides['POST auth/otp/request'] = (_) => http.Response('{}', 429);
    await expectLater(
        session(b, MemoryStore()).requestOtp('+7700'),
        throwsA(isA<PartnerAuthException>()
            .having((e) => e.code, 'code', PartnerAuthException.rateLimited)));
  });

  test('concurrent callers share one refresh (rotating tokens are spent once)',
      () async {
    final b = FakeBackend();
    final s = session(b, storedSession());
    final tokens =
        await Future.wait([s.accessToken(), s.accessToken(), s.accessToken()]);
    expect(tokens.toSet(), {'access-1'});
    expect(b.refreshCount, 1);
  });

  test('the rotated refresh token replaces the old one', () async {
    final b = FakeBackend();
    final store = storedSession();
    await session(b, store).accessToken();
    expect(jsonDecode(store.data['kunde.partner.session.v1']!)['refresh'],
        'refresh-2');
  });

  test('a rejected refresh token clears the session and signals expiry',
      () async {
    final b = FakeBackend()..tokenRefresh = (_) => http.Response('{}', 401);
    final store = storedSession();
    final s = session(b, store);
    var expired = 0;
    s.onExpired = () => expired++;
    await expectLater(s.accessToken(), throwsA(isA<SessionExpiredException>()));
    expect(store.data, isEmpty);
    expect(expired, 1);
  });

  test('a network failure during refresh keeps the stored session', () async {
    final b = FakeBackend()
      ..tokenRefresh = (_) => throw const SocketException('offline');
    final store = storedSession();
    final s = session(b, store);
    await expectLater(
        s.accessToken(),
        throwsA(isA<PartnerAuthException>()
            .having((e) => e.code, 'code', 'NETWORK')));
    expect(store.data, isNotEmpty);
    // connectivity returns: the same session works again
    b.tokenRefresh = null;
    expect(await s.accessToken(), startsWith('access-'));
  });

  test('a server error (5xx) during refresh keeps the session', () async {
    final b = FakeBackend()..tokenRefresh = (_) => http.Response('{}', 503);
    final store = storedSession();
    await expectLater(
        session(b, store).accessToken(), throwsA(isA<PartnerAuthException>()));
    expect(store.data, isNotEmpty);
  });

  test('a session stored for another API base is discarded', () async {
    final store = MemoryStore({
      'kunde.partner.session.v1':
          jsonEncode({'base': 'https://other.test/api/v1/', 'refresh': 'x'}),
    });
    final s = session(FakeBackend(), store);
    expect(await s.hasStoredSession(), isFalse);
    expect(store.data, isEmpty);
  });

  test('corrupt stored state is discarded', () async {
    final store = MemoryStore({'kunde.partner.session.v1': '{not json'});
    expect(await session(FakeBackend(), store).hasStoredSession(), isFalse);
    expect(store.data, isEmpty);
  });

  test('selected partner survives token rotation', () async {
    final b = FakeBackend();
    final store = storedSession(partner: partnerId);
    final s = session(b, store);
    await s.accessToken();
    expect(await s.storedPartnerId(), partnerId);
    await s.rememberPartner(null);
    expect(await s.storedPartnerId(), isNull);
    expect(await s.hasStoredSession(), isTrue);
  });

  test('logout clears local state even when the server is unreachable',
      () async {
    final b = FakeBackend()
      ..overrides['POST auth/logout'] =
          (_) => throw const SocketException('offline');
    final store = storedSession();
    await session(b, store).logout();
    expect(store.data, isEmpty);
  });

  test('timeouts are mapped to TIMEOUT', () async {
    final s = PartnerSession(
      apiBase: apiBase,
      client: MockClient((_) => Completer<http.Response>().future),
      storage: MemoryStore(),
      timeout: const Duration(milliseconds: 50),
    );
    await expectLater(
        s.requestOtp('+7'),
        throwsA(isA<PartnerAuthException>()
            .having((e) => e.code, 'code', 'TIMEOUT')));
  });

  group('shared token-session core: Partner adapter', () {
    test(
        'restores after an app restart: stored partner is readable without network, refresh is lazy',
        () async {
      final b = FakeBackend();
      final store = storedSession(partner: partnerId);
      final restarted = session(b, store);
      expect(await restarted.hasStoredSession(), isTrue);
      expect(await restarted.storedPartnerId(), partnerId);
      expect(b.refreshCount, 0,
          reason: 'reading the stored session needs no network');
      expect(await restarted.accessToken(), 'access-1');
      expect(b.refreshCount, 1);
      expect(jsonDecode(store.data['kunde.partner.session.v1']!)['refresh'],
          'refresh-2');
    });

    test(
        'without any stored session the access token is null and nothing is requested',
        () async {
      final b = FakeBackend();
      expect(await session(b, MemoryStore()).accessToken(), isNull);
      expect(b.calls, isEmpty);
    });

    test(
        'an expired access token is refreshed again; a forced refresh spends the rotating token',
        () async {
      final b = FakeBackend();
      final s = session(b, storedSession());
      expect(await s.accessToken(), 'access-1');
      expect(await s.accessToken(force: true), 'access-2');
      expect(b.refreshCount, 2);
    });

    test(
        'many simultaneous callers with no access token spend the refresh token once',
        () async {
      final b = FakeBackend();
      final s = session(b, storedSession());
      final tokens =
          await Future.wait(List.generate(8, (_) => s.accessToken()));
      expect(tokens.toSet(), {'access-1'});
      expect(b.refreshCount, 1);
    });

    test(
        'an invalid (rejected) refresh token expires the session exactly once and later calls see no session',
        () async {
      var expired = 0;
      final b = FakeBackend()
        ..overrides['POST auth/token/refresh'] =
            (_) => http.Response('{}', 401);
      final store = storedSession(partner: partnerId);
      final s = session(b, store)..onExpired = () => expired++;
      await expectLater(
          s.accessToken(), throwsA(isA<SessionExpiredException>()));
      expect(expired, 1);
      expect(store.data, isEmpty);
      expect(await s.accessToken(), isNull);
      expect(expired, 1);
    });

    test('the chosen partner survives a new sign-in on the same device',
        () async {
      final b = FakeBackend();
      final store = storedSession(partner: partnerId, refresh: 'old');
      final s = session(b, store);
      await s.verifyOtp('+77000000002', '123456');
      expect(await s.storedPartnerId(), partnerId);
    });

    test(
        'logout sends the stored refresh token to the server and clears local state',
        () async {
      final b = FakeBackend();
      final store =
          storedSession(partner: partnerId, refresh: 'refresh-to-revoke');
      await session(b, store).logout();
      expect(b.count('POST auth/logout'), 1);
      expect(store.data, isEmpty);
    });

    test(
        'the Partner session never touches the Consumer key and ignores a Consumer session',
        () async {
      final b = FakeBackend();
      final store = MemoryStore({
        'kunde.consumer.session.v1': jsonEncode({
          'issuerVersion': 2,
          'context': apiBase.toString(),
          'refresh': 'consumer-refresh'
        }),
      });
      final s = session(b, store);
      expect(await s.hasStoredSession(), isFalse);
      await s.verifyOtp('+77000000002', '123456');
      expect(
          store.data.keys,
          containsAll(
              ['kunde.consumer.session.v1', 'kunde.partner.session.v1']));
      expect(store.data['kunde.consumer.session.v1'],
          contains('consumer-refresh'));
      await s.logout();
      expect(store.data.keys, ['kunde.consumer.session.v1']);
    });

    test('errors raised by the session never carry tokens', () async {
      final b = FakeBackend()
        ..overrides['POST auth/token/refresh'] =
            (_) => throw const SocketException('offline');
      final s = session(b, storedSession(refresh: 'SECRET-REFRESH'));
      Object? failure;
      try {
        await s.accessToken();
      } catch (e) {
        failure = e;
      }
      expect(failure, isA<PartnerAuthException>());
      expect(failure.toString(), isNot(contains('SECRET')));
      expect(const SessionExpiredException().toString(),
          isNot(contains('SECRET')));
    });
  });
}
