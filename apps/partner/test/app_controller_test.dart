import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kunde_partner/app/app_controller.dart';

import 'support/fake_backend.dart';

Map<String, dynamic> partner(String id, String name,
        {String status = 'APPROVED', String role = 'OWNER'}) =>
    {
      'id': id,
      'displayName': name,
      'verificationStatus': status,
      'version': 1,
      'role': role
    };

void main() {
  test('no stored session: starts signed out without any network call',
      () async {
    final h = Harness(signedIn: false);
    await h.controller.bootstrap();
    expect(h.controller.phase, AppPhase.signedOut);
    expect(h.backend.calls, isEmpty);
  });

  test('stored session with one partner restores straight into the workspace',
      () async {
    final h = Harness();
    await h.controller.bootstrap();
    expect(h.controller.phase, AppPhase.ready);
    expect(h.controller.partner?.name, 'Демо-партнёр');
    expect(h.backend.refreshCount, 1);
    // the first protected calls are authenticated with the refreshed token
    expect(
        h.backend.headers.any((x) => x['Authorization'] == 'Bearer access-1'),
        isTrue);
  });

  test('OTP login discovers the partner automatically', () async {
    final h = Harness(signedIn: false);
    await h.controller.verifyOtp('+77000000002', '123456');
    expect(h.controller.phase, AppPhase.ready);
    expect(h.controller.partner?.id, partnerId);
  });

  test(
      'several partners: remembered choice is restored, otherwise the user chooses',
      () async {
    final b = FakeBackend()
      ..partners = [partner('p-a', 'Первый'), partner(partnerId, 'Второй')];
    final fresh = Harness(backend: b, signedIn: false);
    await fresh.controller.verifyOtp('+77000000002', '123456');
    expect(fresh.controller.phase, AppPhase.choosingPartner);
    expect(fresh.controller.partners, hasLength(2));
    await fresh.controller.select(fresh.controller.partners.last);
    expect(fresh.controller.phase, AppPhase.ready);

    final restored =
        Harness(backend: b, store: storedSession(partner: partnerId));
    await restored.controller.bootstrap();
    expect(restored.controller.phase, AppPhase.ready);
    expect(restored.controller.partner?.name, 'Второй');

    final forgotten =
        Harness(backend: b, store: storedSession(partner: 'gone'));
    await forgotten.controller.bootstrap();
    expect(forgotten.controller.phase, AppPhase.choosingPartner);
  });

  test('only APPROVED memberships are offered; none means "no access"',
      () async {
    final b = FakeBackend()
      ..partners = [partner('p1', 'Ждёт', status: 'PENDING')];
    final h = Harness(backend: b, signedIn: false);
    await h.controller.verifyOtp('+77000000002', '123456');
    expect(h.controller.phase, AppPhase.noAccess);
    expect(h.backend.calls.where((c) => c.contains('/food/')), isEmpty,
        reason: 'no partner data is requested without an approved membership');
  });

  test('403 from partner discovery shows "no access", not an error crash',
      () async {
    final b = FakeBackend();
    b.overrides['GET partner/partners'] = (_) => b.error(403, 'FORBIDDEN');
    final h = Harness(backend: b, signedIn: false);
    await h.controller.verifyOtp('+77000000002', '123456');
    expect(h.controller.phase, AppPhase.noAccess);
  });

  test('offline at start-up keeps the session and offers a retry', () async {
    final b = FakeBackend()
      ..tokenRefresh = (_) => throw const SocketException('offline');
    final h = Harness(backend: b);
    await h.controller.bootstrap();
    expect(h.controller.phase, AppPhase.unreachable);
    expect(h.store.data, isNotEmpty,
        reason: 'session must survive a network outage');
    b.tokenRefresh = null;
    await h.controller.retryRestore();
    expect(h.controller.phase, AppPhase.ready);
  });

  test('an expired refresh token sends the user to login with a notice',
      () async {
    final b = FakeBackend()..tokenRefresh = (_) => http.Response('{}', 401);
    final h = Harness(backend: b);
    await h.controller.bootstrap();
    expect(h.controller.phase, AppPhase.signedOut);
    expect(h.controller.notice, SignOutNotice.sessionExpired);
    expect(h.store.data, isEmpty);
  });

  test('revoked staff access (404 PARTNER_NOT_FOUND) leaves the workspace',
      () async {
    final b = FakeBackend();
    final h = Harness(backend: b);
    await h.controller.bootstrap();
    expect(h.controller.phase, AppPhase.ready);
    // The owner removes this staff member: discovery now returns nothing
    // and partner endpoints answer 404.
    b.partners = [];
    b.overrides['GET partner/partners/$partnerId/food/orders'] =
        (_) => b.error(404, 'PARTNER_NOT_FOUND');
    await h.controller.store!.refreshActiveOrders();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(h.controller.phase, AppPhase.noAccess);
    expect(h.controller.notice, SignOutNotice.accessRevoked);
  });

  test('logout clears state and signs out on the server', () async {
    final h = Harness();
    await h.controller.bootstrap();
    await h.controller.logout();
    expect(h.controller.phase, AppPhase.signedOut);
    expect(h.store.data, isEmpty);
    expect(h.backend.calls, contains('POST auth/logout'));
  });

  test(
      'a 401 on a protected call with a dead refresh token expires the session',
      () async {
    final b = FakeBackend();
    final h = Harness(backend: b);
    await h.controller.bootstrap();
    b.overrides['GET partner/partners/$partnerId/food/orders'] =
        (_) => b.error(401, 'UNAUTHORIZED');
    b.tokenRefresh = (_) => http.Response('{}', 401);
    await h.controller.store!.refreshActiveOrders();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(h.controller.phase, AppPhase.signedOut);
    expect(h.controller.notice, SignOutNotice.sessionExpired);
  });
}
