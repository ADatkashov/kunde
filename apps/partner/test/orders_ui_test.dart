import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:kunde_partner/features/orders/order_details_page.dart';

import 'support/fake_backend.dart';
import 'support/pump.dart';

void main() {
  testWidgets(
      'new order card shows items, total, number and the reply deadline',
      (tester) async {
    final h = Harness();
    await pumpReady(tester, h);
    expect(find.text('Новые'), findsOneWidget);
    expect(find.textContaining('2× Лагман'), findsOneWidget);
    expect(find.textContaining('4 100 ₸'), findsWidgets);
    expect(find.textContaining('Ответить до'), findsOneWidget);
    expect(find.text('Принять заказ'), findsOneWidget);
    expect(find.text('Отклонить'), findsOneWidget);
    // no technical identifiers or raw codes for the business owner
    expect(find.textContaining(orderId), findsNothing);
    expect(find.text('PLACED'), findsNothing);
    expect(find.textContaining('{'), findsNothing);
  });

  testWidgets(
      'accepting asks for confirmation, then moves the order to "In progress"',
      (tester) async {
    final h = Harness();
    await pumpReady(tester, h);
    await tester.tap(find.text('Принять заказ'));
    await tester.pumpAndSettle();
    expect(find.text('Принять этот заказ?'), findsOneWidget);
    // backing out sends nothing
    await tester.tap(find.text('Назад'));
    await tester.pumpAndSettle();
    expect(h.backend.count('POST partner/'), 0);

    await tester.tap(find.text('Принять заказ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Подтвердить'));
    await settle(tester);
    expect(
        h.backend.count(
            'POST partner/partners/$partnerId/food/orders/$orderId/status'),
        1);
    expect(find.text('Статус заказа обновлён'), findsOneWidget);
  });

  testWidgets('a reject needs a reason of at least three characters',
      (tester) async {
    final h = Harness();
    await pumpReady(tester, h);
    await tester.tap(find.text('Отклонить').first);
    await tester.pumpAndSettle();
    expect(find.text('Отклонить заказ'), findsOneWidget);
    FilledButton confirm() => tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Подтвердить'));
    expect(confirm().onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'ab');
    await tester.pump();
    expect(confirm().onPressed, isNull);
    await tester.tap(find.text('Блюдо закончилось'));
    await tester.pump();
    expect(confirm().onPressed, isNotNull);
    await tester.tap(find.widgetWithText(FilledButton, 'Подтвердить'));
    await settle(tester);
    expect(h.backend.count('POST partner/'), 1);
    expect(h.backend.calls.last, contains('/status'));
  });

  testWidgets('rejected order appears under Completed with its reason',
      (tester) async {
    final h = Harness();
    await pumpReady(tester, h);
    await tester.tap(find.text('Отклонить').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Кухня закрыта');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Подтвердить'));
    await settle(tester);
    await tester.tap(find.text('Завершённые'));
    await tester.pumpAndSettle();
    expect(find.text('Отменён'), findsOneWidget);
    expect(find.textContaining('Кухня закрыта'), findsOneWidget);
  });

  testWidgets(
      'server conflict is explained in plain words and the list refreshes',
      (tester) async {
    final b = FakeBackend();
    final h = Harness(backend: b);
    await pumpReady(tester, h);
    b.overrides[
            'POST partner/partners/$partnerId/food/orders/$orderId/status'] =
        (_) => b.error(409, 'ORDER_TRANSITION_INVALID');
    b.activeOrders = [
      orderEntry(
          status: 'CANCELLED',
          allowedNext: const [],
          cancelReason: 'PARTNER_TIMEOUT')
    ];
    await tester.tap(find.text('Принять заказ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Подтвердить'));
    await settle(tester, ms: 80);
    expect(find.textContaining('Статус уже изменился'), findsOneWidget);
    expect(find.textContaining('409'), findsNothing);
    expect(find.textContaining('ORDER_TRANSITION'), findsNothing);
  });

  testWidgets(
      'the cards follow the server: no action buttons when allowedNext is empty',
      (tester) async {
    final b = FakeBackend()
      ..activeOrders = [
        orderEntry(
            status: 'PREPARING', allowedNext: const ['ON_THE_WAY', 'CANCELLED'])
      ];
    final h = Harness(backend: b);
    await pumpReady(tester, h);
    await tester.tap(find.text('В работе'));
    await tester.pumpAndSettle();
    expect(find.text('Передать в доставку'), findsOneWidget);
    expect(find.text('Принять заказ'), findsNothing);
    expect(find.text('Готовится'), findsOneWidget);
  });

  testWidgets('order details show items, totals, address, comment and history',
      (tester) async {
    final h = Harness();
    await pumpReady(tester, h);
    await tester.tap(find.textContaining('2× Лагман'));
    await tester.pumpAndSettle();
    expect(find.text('Состав заказа'), findsOneWidget);
    expect(find.text('Острый'), findsOneWidget);
    expect(find.text('ул. Абая 10, кв. 5'), findsOneWidget);
    expect(find.text('Без лука'), findsOneWidget);
    expect(find.text('Оплата при получении'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('История статусов'), 200,
        scrollable: find.descendant(
            of: find.byType(OrderDetailsPage),
            matching: find.byType(Scrollable)));
    expect(find.text('История статусов'), findsOneWidget);
    expect(find.textContaining(orderId), findsNothing);
    // actions are available from the details as well
    expect(find.text('Принять заказ'), findsOneWidget);
  });

  testWidgets('empty states are friendly, not blank', (tester) async {
    final b = FakeBackend()..activeOrders = [];
    final h = Harness(backend: b);
    await pumpReady(tester, h);
    expect(find.text('Новых заказов нет'), findsOneWidget);
    await tester.tap(find.text('В работе'));
    await tester.pumpAndSettle();
    expect(find.text('Нет заказов в работе'), findsOneWidget);
    await tester.tap(find.text('Завершённые'));
    await tester.pumpAndSettle();
    expect(find.text('Завершённых заказов пока нет'), findsOneWidget);
  });

  testWidgets(
      'offline first load shows a retryable error; retry succeeds after reconnect',
      (tester) async {
    final b = FakeBackend();
    var offline = true;
    b.overrides[
            'GET partner/partners/$partnerId/food/orders?scope=active&limit=100&offset=0'] =
        (_) {
      if (offline) throw const SocketException('offline');
      return b.json([orderEntry()]);
    };
    final h = Harness(backend: b);
    await pumpReady(tester, h, tab: null);
    await tester.tap(find.descendant(
        of: find.byType(NavigationBar), matching: find.text('Заказы')));
    await settle(tester, ms: 200);
    expect(find.text('Нет соединения'), findsWidgets);
    expect(find.textContaining('SocketException'), findsNothing);
    offline = false;
    await tester.tap(find.text('Повторить').first);
    await settle(tester, ms: 80);
    expect(find.textContaining('2× Лагман'), findsOneWidget);
  });

  testWidgets(
      'stale data stays visible with an offline banner when a refresh fails',
      (tester) async {
    final b = FakeBackend();
    final h = Harness(backend: b);
    await pumpReady(tester, h);
    b.overrides[
            'GET partner/partners/$partnerId/food/orders?scope=active&limit=100&offset=0'] =
        (_) => http.Response('{}', 503);
    await tester.runAsync(() => h.controller.store!.refreshActiveOrders());
    await tester.pump();
    expect(find.textContaining('2× Лагман'), findsOneWidget);
    expect(find.textContaining('Сервис временно недоступен'), findsOneWidget);
  });

  testWidgets(
      'picking: lines are marked picked or missing, replacements need a choice',
      (tester) async {
    final h = Harness();
    h.backend.activeOrders = [
      orderEntry(
          status: 'PREPARING',
          allowedNext: const ['READY_FOR_PICKUP', 'ON_THE_WAY'],
          picks: h.backend.picks),
    ];
    await pumpReady(tester, h);
    await tester.tap(find.text('В работе'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Лагман'));
    await tester.pumpAndSettle();
    expect(find.text('Собрано'), findsNWidgets(2));
    await tester.tap(find.text('Собрано').first);
    await settle(tester);
    expect(
        h.backend.count(
            'POST partner/partners/$partnerId/food/orders/$orderId/items/item-1/pick'),
        1);
    expect(h.backend.picks['item-1'], 'OK');
    await tester.tap(find.text('Нет в наличии'));
    await settle(tester);
    expect(h.backend.picks['item-2'], 'REMOVED');
    expect(find.text('Собрано'), findsWidgets);
  });
}
