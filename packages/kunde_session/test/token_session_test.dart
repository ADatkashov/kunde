import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_session/kunde_session.dart';

class _MemoryPersistence implements SessionPersistence {
  StoredSession? value;
  Object? loadError;
  int clears = 0;
  @override
  Future<StoredSession?> load() async {
    if (loadError != null) throw loadError!;
    return value;
  }

  @override
  Future<void> save(StoredSession session) async => value = session;
  @override
  Future<void> clear() async {
    clears++;
    value = null;
  }
}

class _Refresher implements TokenRefresher {
  _Refresher(this.clock);
  final DateTime Function() clock;
  final List<String> used = [];
  int generation = 0;
  Object? failure;
  Completer<void>? gate;
  Map<String, String> extras = const {};
  @override
  Future<IssuedTokens> refresh(String refreshToken) async {
    used.add(refreshToken);
    await gate?.future;
    if (failure != null) throw failure!;
    generation++;
    return IssuedTokens(
      access: 'access-$generation',
      refresh: 'refresh-$generation',
      expires: clock().add(const Duration(minutes: 5)),
      extras: extras,
    );
  }
}

void main() {
  late DateTime now;
  late _MemoryPersistence store;
  late _Refresher refresher;
  late TokenSession session;

  IssuedTokens tokens(String access, String refresh,
          {int minutes = 5, Map<String, String> extras = const {}}) =>
      IssuedTokens(
          access: access,
          refresh: refresh,
          expires: now.add(Duration(minutes: minutes)),
          extras: extras);

  TokenSession build({bool carry = false}) => TokenSession(
      persistence: store,
      refresher: refresher,
      carryExtrasAcrossSignIn: carry,
      clock: () => now);

  setUp(() {
    now = DateTime.utc(2026, 11, 24, 12);
    store = _MemoryPersistence();
    refresher = _Refresher(() => now);
    session = build();
  });

  test(
      'signIn stores the refresh token and serves the access token without a refresh',
      () async {
    await session.signIn(tokens('a1', 'r1'));
    expect(session.authenticated, isTrue);
    expect(store.value!.refresh, 'r1');
    expect(await session.accessToken(), 'a1');
    expect(refresher.used, isEmpty);
  });

  test(
      'an access token near expiry is refreshed and the rotated refresh token is persisted',
      () async {
    await session.signIn(tokens('a1', 'r1', minutes: 1));
    now = now.add(const Duration(seconds: 45)); // inside the 30 s leeway
    expect(await session.accessToken(), 'access-1');
    expect(refresher.used, ['r1']);
    expect(store.value!.refresh, 'refresh-1');
  });

  test(
      'concurrent callers with an expired token share one refresh (rotation is spent once)',
      () async {
    await session.signIn(tokens('a1', 'r1', minutes: 0));
    refresher.gate = Completer<void>();
    final calls = [
      session.accessToken(),
      session.accessToken(),
      session.accessToken(),
      session.accessToken()
    ];
    await Future<void>.delayed(Duration.zero);
    refresher.gate!.complete();
    final results = await Future.wait(calls);
    expect(results.toSet(), {'access-1'});
    expect(refresher.used, ['r1']);
  });

  test('restore after a restart refreshes the stored session', () async {
    store.value = const StoredSession('r-old');
    await session.restore();
    expect(session.authenticated, isTrue);
    expect(refresher.used, ['r-old']);
    expect(store.value!.refresh, 'refresh-1');
  });

  test('a lazy accessToken works from the stored session without restore',
      () async {
    store.value = const StoredSession('r-old', {'partnerId': 'p1'});
    expect(await session.accessToken(), 'access-1');
    expect(store.value!.extras['partnerId'], 'p1');
  });

  test('no session at all is SessionMissing', () async {
    await expectLater(session.accessToken(), throwsA(isA<SessionMissing>()));
  });

  test(
      'a rejected refresh token clears the session, marks it expired and calls onExpired once',
      () async {
    var expiredCalls = 0;
    session.onExpired = () => expiredCalls++;
    await session.signIn(tokens('a1', 'r1', minutes: 0));
    refresher.failure = const SessionRejected();
    await expectLater(session.accessToken(), throwsA(isA<SessionRejected>()));
    expect(session.authenticated, isFalse);
    expect(session.expired, isTrue);
    expect(store.value, isNull);
    expect(expiredCalls, 1);
    await expectLater(session.accessToken(), throwsA(isA<SessionMissing>()));
    expect(expiredCalls, 1);
  });

  test('a transient failure keeps the session and the stored refresh token',
      () async {
    await session.signIn(tokens('a1', 'r1', minutes: 0));
    refresher.failure = const SessionUnavailable('offline');
    await expectLater(
        session.accessToken(), throwsA(isA<SessionUnavailable>()));
    expect(session.authenticated, isTrue);
    expect(store.value!.refresh, 'r1');
    refresher.failure = null;
    expect(await session.accessToken(), 'access-1');
  });

  test('restore keeps the stored token on an outage and can be retried',
      () async {
    store.value = const StoredSession('r1');
    refresher.failure = const SessionUnavailable();
    await expectLater(session.restore(), throwsA(isA<SessionUnavailable>()));
    expect(session.authenticated, isFalse);
    expect(store.value!.refresh, 'r1');
    refresher.failure = null;
    await session.restore();
    expect(session.authenticated, isTrue);
  });

  test(
      'unreadable or foreign stored state fails closed: the session is cleared and expired',
      () async {
    store.value = const StoredSession('r1');
    store.loadError = const SessionRejected();
    await session.restore();
    expect(session.authenticated, isFalse);
    expect(session.expired, isTrue);
    expect(refresher.used, isEmpty);
    expect(store.clears, 1);
  });

  test('an unexpected refresher error propagates and does not log the user out',
      () async {
    await session.signIn(tokens('a1', 'r1', minutes: 0));
    refresher.failure = StateError('boom');
    await expectLater(session.accessToken(), throwsA(isA<StateError>()));
    expect(session.authenticated, isTrue);
    expect(store.value!.refresh, 'r1');
  });

  test('extras survive refresh; new issued extras override', () async {
    await session.signIn(tokens('a1', 'r1',
        minutes: 0, extras: {'id': 'idt', 'partnerId': 'p1'}));
    refresher.extras = {'id': 'idt2'};
    await session.accessToken();
    expect(store.value!.extras, {'id': 'idt2', 'partnerId': 'p1'});
  });

  test('sign-in carries stored extras only when the adapter asks for it',
      () async {
    store.value = const StoredSession('old', {'partnerId': 'p1'});
    await session.signIn(tokens('a', 'r'));
    expect(store.value!.extras, isEmpty);

    store.value = const StoredSession('old', {'partnerId': 'p1'});
    session = build(carry: true);
    await session.signIn(tokens('a', 'r'));
    expect(store.value!.extras, {'partnerId': 'p1'});
  });

  test('updateExtras changes the stored session and ignores a missing one',
      () async {
    await session.updateExtras({'partnerId': 'p9'});
    expect(store.value, isNull);
    await session.signIn(tokens('a', 'r'));
    await session.updateExtras({'partnerId': 'p9'});
    expect(store.value!.extras['partnerId'], 'p9');
    await session.updateExtras({'partnerId': null});
    expect(store.value!.extras, isEmpty);
  });

  test(
      'a 401 for the current access token ends the session; a stale one does not',
      () async {
    await session.signIn(tokens('a1', 'r1'));
    await session.rejectIfCurrent('old-access');
    expect(session.authenticated, isTrue);
    await session.rejectIfCurrent('a1');
    expect(session.authenticated, isFalse);
    expect(session.expired, isTrue);
  });

  test(
      'signOut clears locally first, revokes with the refresh token and reports a server failure',
      () async {
    await session.signIn(tokens('a1', 'r1', extras: {'id': 'idt'}));
    String? revoked;
    var stillStoredDuringRevoke = true;
    final ok = await session.signOut(revoke: (stored) async {
      revoked = '${stored.refresh}|${stored.extras['id']}';
      stillStoredDuringRevoke = store.value != null;
    });
    expect(ok, isTrue);
    expect(revoked, 'r1|idt');
    expect(stillStoredDuringRevoke, isFalse);
    expect(session.authenticated, isFalse);
    expect(session.expired, isFalse);

    await session.signIn(tokens('a2', 'r2'));
    expect(
        await session.signOut(revoke: (_) async => throw StateError('offline')),
        isFalse);
    expect(store.value, isNull);
  });

  test('signOut works from a stored session that was never loaded', () async {
    store.value = const StoredSession('r-stored');
    String? revoked;
    await session.signOut(revoke: (s) async => revoked = s.refresh);
    expect(revoked, 'r-stored');
    expect(store.value, isNull);
  });

  test('failed interactive login discard does not mark the session expired',
      () async {
    await session.discard();
    expect(session.expired, isFalse);
  });

  test('sessions with separate persistence never see each other', () async {
    final other = _MemoryPersistence();
    final otherSession = TokenSession(
        persistence: other, refresher: refresher, clock: () => now);
    await session.signIn(tokens('a-consumer', 'r-consumer'));
    expect(await otherSession.peek(), isNull);
    await expectLater(
        otherSession.accessToken(), throwsA(isA<SessionMissing>()));
    await otherSession.signIn(tokens('a-partner', 'r-partner'));
    await session.signOut();
    expect(other.value!.refresh, 'r-partner');
    expect(await otherSession.accessToken(), 'a-partner');
  });

  test('tokens never appear in toString or error text', () {
    final issued = tokens('SECRET-ACCESS', 'SECRET-REFRESH');
    final texts = [
      issued.toString(),
      const StoredSession('SECRET-REFRESH', {'id': 'SECRET-ID'}).toString(),
      const SessionRejected('x').toString(),
      const SessionUnavailable().toString(),
      const SessionMissing().toString(),
    ];
    for (final text in texts) {
      expect(text, isNot(contains('SECRET')));
    }
  });
}
