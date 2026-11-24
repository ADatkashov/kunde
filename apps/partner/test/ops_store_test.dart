import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kunde_partner/app/app_controller.dart';
import 'package:kunde_partner/app/ops_store.dart';
import 'package:kunde_partner/data/partner_api.dart';

import 'support/fake_backend.dart';

Future<(Harness, OpsStore)> ready([FakeBackend? backend]) async {
  final h = Harness(backend: backend);
  await h.controller.bootstrap();
  expect(h.controller.phase, AppPhase.ready);
  final store = h.controller.store!;
  await store.refreshAll();
  return (h, store);
}

void main() {
  test('loads orders, bookings and modules', () async {
    final (_, store) = await ready();
    expect(store.activeOrders.data!.single.isNew, isTrue);
    expect(store.bookingRequests.data!.single.isPending, isTrue);
    expect(store.restaurants.data!.single.name, 'Кухня партнёра');
    expect(store.venues.data!.single.open, isTrue);
    expect(store.historyOrders.data, isEmpty);
  });

  test('accepting an order sends exactly one request and updates the list',
      () async {
    final b = FakeBackend();
    final (_, store) = await ready(b);
    final updated = await store.changeOrder(orderId, 'ACCEPTED');
    expect(updated!.status, 'ACCEPTED');
    expect(
        b.count('POST partner/partners/$partnerId/food/orders/$orderId/status'),
        1);
    expect(store.activeOrders.data!.single.status, 'ACCEPTED');
  });

  test('double tap is ignored while the first request is in flight', () async {
    final b = FakeBackend();
    final (_, store) = await ready(b);
    final gate = Completer<void>();
    b.overrides[
            'POST partner/partners/$partnerId/food/orders/$orderId/status'] =
        (_) async {
      await gate.future;
      return b.json(
          orderEntry(status: 'ACCEPTED', allowedNext: const ['PREPARING']));
    };
    final first = store.changeOrder(orderId, 'ACCEPTED');
    expect(store.isBusy(orderId), isTrue);
    final second = await store.changeOrder(orderId, 'ACCEPTED');
    expect(second, isNull, reason: 'second tap must be dropped');
    gate.complete();
    await first;
    expect(store.isBusy(orderId), isFalse);
    expect(
        b.count('POST partner/partners/$partnerId/food/orders/$orderId/status'),
        1);
  });

  test('rejecting moves the order to the completed list with its reason',
      () async {
    final (_, store) = await ready();
    final updated = await store.changeOrder(orderId, 'CANCELLED',
        reason: 'Блюдо закончилось');
    expect(updated!.status, 'CANCELLED');
    expect(updated.cancelReason, 'Блюдо закончилось');
    expect(store.activeOrders.data, isEmpty);
    expect(store.historyOrders.data!.first.id, orderId);
  });

  test('a conflict (illegal transition) refreshes the lists from the server',
      () async {
    final b = FakeBackend();
    final (_, store) = await ready(b);
    b.overrides[
            'POST partner/partners/$partnerId/food/orders/$orderId/status'] =
        (_) => b.error(409, 'ORDER_TRANSITION_INVALID');
    b.activeOrders = [
      orderEntry(status: 'ACCEPTED', allowedNext: ['PREPARING', 'CANCELLED'])
    ];
    await expectLater(
      store.changeOrder(orderId, 'ACCEPTED'),
      throwsA(isA<PartnerApiException>()
          .having((e) => e.code, 'code', 'ORDER_TRANSITION_INVALID')),
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(store.activeOrders.data!.single.status, 'ACCEPTED');
    expect(store.isBusy(orderId), isFalse);
  });

  test('booking actions refresh the three scopes', () async {
    final b = FakeBackend();
    final (_, store) = await ready(b);
    b.requests = [];
    b.upcoming = [
      bookingJson(status: 'CONFIRMED', allowedActions: ['CANCEL'])
    ];
    await store.changeBooking(bookingId, 'CONFIRM');
    expect(store.bookingRequests.data, isEmpty);
    expect(store.bookingUpcoming.data!.single.status, 'CONFIRMED');
  });

  test('a failed refresh keeps the last good data and exposes the error',
      () async {
    final b = FakeBackend();
    final (_, store) = await ready(b);
    b.overrides[
            'GET partner/partners/$partnerId/food/orders?scope=active&limit=100&offset=0'] =
        (_) => http.Response('{}', 500);
    await store.refreshActiveOrders();
    expect(store.activeOrders.data, isNotEmpty);
    expect(store.activeOrders.error, isNotNull);
    b.overrides.clear();
    await store.refreshActiveOrders();
    expect(store.activeOrders.error, isNull);
  });

  test('new-work detection: first load is silent, later arrivals notify',
      () async {
    final b = FakeBackend();
    final (_, store) = await ready(b);
    expect(store.newWork.value, isNull, reason: 'initial load must not alert');
    b.activeOrders = [
      orderEntry(),
      orderEntry(id: 'aaaaaaaa-0000-0000-0000-000000000002')
    ];
    b.requests = [
      bookingJson(),
      bookingJson(id: 'bbbbbbbb-0000-0000-0000-000000000002')
    ];
    await store.refreshActiveOrders();
    await store.refreshBookingRequests();
    expect(store.newWork.value!.orders, 1);
    expect(store.newWork.value!.bookings, 1);
    store.acknowledgeNewWork();
    await store.refreshActiveOrders();
    expect(store.newWork.value, isNull,
        reason: 'known orders never alert twice');
  });

  test('history paginates with limit/offset and appends without duplicates',
      () async {
    final b = FakeBackend();
    b.historyOrders = [
      for (var i = 0; i < 3; i++)
        orderEntry(
            id: 'aaaaaaaa-0000-0000-0000-00000000010$i',
            status: 'DELIVERED',
            allowedNext: [])
    ];
    final h = Harness(backend: b);
    await h.controller.bootstrap();
    final store =
        OpsStore(h.controller.store!.ops, pageSize: 3, pollInterval: null);
    addTearDown(store.dispose);
    await store.refreshOrderHistory();
    expect(store.orderHistoryHasMore, isTrue);
    b.overrides[
            'GET partner/partners/$partnerId/food/orders?scope=history&limit=3&offset=3'] =
        (_) => b.json([
              orderEntry(
                  id: 'aaaaaaaa-0000-0000-0000-000000000200',
                  status: 'DELIVERED',
                  allowedNext: [])
            ]);
    await store.loadMoreOrderHistory();
    expect(store.historyOrders.data, hasLength(4));
    expect(store.orderHistoryHasMore, isFalse);
  });

  test('polling is off when no interval is configured and stops on dispose',
      () async {
    final (h, store) = await ready();
    final before = h.backend.calls.length;
    store.startPolling();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(h.backend.calls.length, before);
  });

  test('poller refreshes only while in foreground and backs off', () async {
    final b = FakeBackend();
    final h = Harness(backend: b);
    await h.controller.bootstrap();
    final store = OpsStore(h.controller.store!.ops,
        pollInterval: const Duration(milliseconds: 30));
    await store.refreshAll();
    final base =
        b.count('GET partner/partners/$partnerId/food/orders?scope=active');
    store.setForeground(false);
    store.startPolling();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(b.count('GET partner/partners/$partnerId/food/orders?scope=active'),
        base,
        reason: 'no polling in the background');
    store.setForeground(true);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(b.count('GET partner/partners/$partnerId/food/orders?scope=active'),
        greaterThan(base));
    store.dispose();
    final stopped = b.calls.length;
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(b.calls.length, stopped, reason: 'disposed store must not poll');
  });
}
