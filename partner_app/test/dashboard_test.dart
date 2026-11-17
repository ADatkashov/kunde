import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_partner/app/app_controller.dart';
import 'package:kunde_partner/features/dashboard/dashboard_stats.dart';

import 'support/fake_backend.dart';
import 'support/pump.dart';

Map<String, dynamic> delivered(String id, int totalMinor, DateTime at) {
  final e = orderEntry(
      id: id,
      status: 'DELIVERED',
      allowedNext: const [],
      placedAt: at.subtract(const Duration(minutes: 40)));
  final order = e['order'] as Map<String, dynamic>;
  order['totalMinor'] = totalMinor;
  order['timeline'] = [
    {
      'status': 'PLACED',
      'at': at.subtract(const Duration(minutes: 40)).toUtc().toIso8601String(),
      'actor': 'CUSTOMER'
    },
    {
      'status': 'DELIVERED',
      'at': at.toUtc().toIso8601String(),
      'actor': 'PARTNER'
    },
  ];
  return e;
}

void main() {
  testWidgets(
      'home shows attention card, real counters, quick actions and events',
      (tester) async {
    final now = DateTime.now();
    final b = FakeBackend()
      ..historyOrders = [
        delivered('aaaaaaaa-0000-0000-0000-000000000011', 250000,
            now.subtract(const Duration(minutes: 5))),
        delivered('aaaaaaaa-0000-0000-0000-000000000012', 150000,
            now.subtract(const Duration(minutes: 20))),
      ];
    final h = Harness(backend: b);
    await pumpReady(tester, h, tab: null);
    expect(find.text('Демо-партнёр'), findsWidgets);
    expect(find.text('Требует внимания'), findsOneWidget);
    expect(find.text('Новых заказов: 1'), findsOneWidget);
    expect(find.text('Заявок на запись: 1'), findsOneWidget);
    expect(find.textContaining('Ответить до'), findsOneWidget);
    // KPIs: 2 delivered today → revenue 4 000 ₸ (250000+150000 minor = 4000.00)
    expect(find.text('4 000 ₸'), findsOneWidget);
    expect(find.text('Завершено сегодня'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Последние события'), 300);
    expect(find.textContaining('Заказ № '), findsWidgets);
    expect(find.textContaining('{'), findsNothing);
  });

  testWidgets('all-clear state when nothing needs attention', (tester) async {
    final b = FakeBackend()
      ..activeOrders = []
      ..requests = [];
    final h = Harness(backend: b);
    await pumpReady(tester, h, tab: null);
    expect(find.text('Всё спокойно'), findsOneWidget);
    expect(find.text('Требует внимания'), findsNothing);
  });

  testWidgets('attention button opens the orders tab', (tester) async {
    final h = Harness();
    await pumpReady(tester, h, tab: null);
    await tester.tap(find.widgetWithText(FilledButton, 'Заказы'));
    await tester.pumpAndSettle();
    expect(find.text('Новые'), findsOneWidget);
    expect(find.textContaining('2× Лагман'), findsOneWidget);
  });

  testWidgets('a restaurant-only partner sees no booking widgets',
      (tester) async {
    final b = FakeBackend()
      ..venues = []
      ..requests = [];
    final h = Harness(backend: b);
    await pumpReady(tester, h, tab: null);
    expect(find.text('Заявок на запись: 0'), findsNothing);
    expect(find.text('Заявки на запись'), findsNothing);
    expect(find.text('Предстоящие записи'), findsNothing);
    expect(find.text('Новые заказы'), findsOneWidget);
  });

  testWidgets('pull-to-refresh reloads the dashboard data', (tester) async {
    final b = FakeBackend();
    final h = Harness(backend: b);
    await pumpReady(tester, h, tab: null);
    final before =
        b.count('GET partner/partners/$partnerId/food/orders?scope=active');
    await tester.fling(find.byType(ListView).first, const Offset(0, 400), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    expect(b.count('GET partner/partners/$partnerId/food/orders?scope=active'),
        greaterThan(before));
  });

  testWidgets('dashboard is readable at 200% text without overflow',
      (tester) async {
    final h = Harness();
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await pumpReady(tester, h, tab: null);
    expect(tester.takeException(), isNull);
  });

  test('stats are derived only from loaded data; partial history is flagged',
      () async {
    final now = DateTime.now();
    final b = FakeBackend()
      ..historyOrders = [
        for (var i = 0; i < 2; i++)
          delivered('aaaaaaaa-0000-0000-0000-00000000002$i', 100000,
              now.subtract(Duration(minutes: i + 1))),
      ];
    final h = Harness(backend: b);
    await h.controller.bootstrap();
    final store = h.controller.store!;
    await store.refreshAll();
    var stats = DashboardStats.from(store, now);
    expect(stats.newOrders, 1);
    expect(stats.pendingRequests, 1);
    expect(stats.completedOrdersToday, 2);
    expect(stats.revenueTodayMinor, 200000);
    expect(stats.revenueComplete, isTrue);
    expect(stats.events, isNotEmpty);
    expect(
        stats.events.first.at.isAfter(stats.events.last.at) ||
            stats.events.first.at == stats.events.last.at,
        isTrue);

    // a full page whose oldest entry is still today → total may be incomplete
    store.orderHistoryHasMore = true;
    stats = DashboardStats.from(store, now);
    expect(stats.revenueComplete, isFalse);
    expect(h.controller.phase, AppPhase.ready);
  });
}
