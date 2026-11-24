import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_partner/core/strings.dart';

import 'support/fake_backend.dart';
import 'support/pump.dart';

void main() {
  testWidgets('bottom navigation switches tabs and keeps their state',
      (tester) async {
    final h = Harness();
    await pumpReady(tester, h);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Новые'), findsOneWidget);
    await tester.tap(find.descendant(
        of: find.byType(NavigationBar), matching: find.text('Записи')));
    await tester.pumpAndSettle();
    expect(find.text('Заявки (1)'), findsOneWidget);
    await tester.tap(find.descendant(
        of: find.byType(NavigationBar), matching: find.text('Заведение')));
    await tester.pumpAndSettle();
    expect(find.text('Кухня партнёра'), findsOneWidget);
    expect(find.text('Барбершоп партнёра'), findsOneWidget);
    await tester.tap(find.descendant(
        of: find.byType(NavigationBar), matching: find.text('Профиль')));
    await tester.pumpAndSettle();
    expect(find.text('Демо-партнёр'), findsOneWidget);
    expect(find.textContaining('Владелец'), findsOneWidget);
  });

  testWidgets('new-order badge on the Orders tab', (tester) async {
    final h = Harness();
    await pumpReady(tester, h);
    expect(
        find.descendant(
            of: find.byType(NavigationBar), matching: find.byType(Badge)),
        findsWidgets);
  });

  testWidgets('language switch re-renders the whole UI in Kazakh and English',
      (tester) async {
    final h = Harness();
    await pumpReady(tester, h);
    await h.settings.setLocale(const Locale('kk'));
    await tester.pumpAndSettle();
    expect(find.text('Жаңа'), findsWidgets);
    expect(find.text('Тапсырыстар'), findsWidgets);
    await h.settings.setLocale(const Locale('en'));
    await tester.pumpAndSettle();
    expect(find.text('Orders'), findsWidgets);
    expect(find.text('Accept order'), findsOneWidget);
    expect(find.textContaining('Reply by'), findsOneWidget);
  });

  testWidgets('logout asks for confirmation and returns to login',
      (tester) async {
    final h = Harness();
    await pumpReady(tester, h);
    await tester.tap(find.descendant(
        of: find.byType(NavigationBar), matching: find.text('Профиль')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Выйти'), 200);
    await tester.tap(find.text('Выйти'));
    await tester.pumpAndSettle();
    expect(find.text('Выйти из аккаунта партнёра?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Выйти'));
    await settle(tester);
    expect(find.text('Вход для партнёров'), findsOneWidget);
    expect(h.store.data, isEmpty, reason: 'tokens must be wiped on logout');
  });

  test('every text exists in all three languages and statuses have labels', () {
    for (final code in ['ru', 'kk', 'en']) {
      final s = S(Locale(code));
      final all = <String>[
        s.navHome,
        s.navOrders,
        s.navBookings,
        s.navBusiness,
        s.navProfile,
        s.retry,
        s.loginTitle,
        s.getCode,
        s.signIn,
        s.wrongCode,
        s.errNetworkBody,
        s.errConflict,
        s.tabNew,
        s.tabInProgress,
        s.tabCompleted,
        s.tabRequests,
        s.tabUpcoming,
        s.tabHistory,
        s.logout,
        s.theme,
        s.language,
        s.timeoutReason,
        s.replyBy('12:00'),
        s.minutesLeftText(3),
        s.codeSentTo('+7'),
        for (final st in [
          'PLACED',
          'ACCEPTED',
          'PREPARING',
          'ON_THE_WAY',
          'DELIVERED',
          'CANCELLED'
        ]) ...[
          s.orderStatus(st),
          s.orderAction(st == 'PLACED' ? 'ACCEPTED' : st)
        ],
        for (final st in ['PENDING', 'CONFIRMED', 'COMPLETED', 'CANCELLED'])
          s.bookingStatus(st),
        for (final a in ['CONFIRM', 'REJECT', 'CANCEL', 'COMPLETE'])
          s.bookingAction(a),
        for (final r in ['OWNER', 'MANAGER', 'OPERATOR']) s.role(r),
      ];
      for (final text in all) {
        expect(text.trim(), isNotEmpty, reason: code);
        expect(text, isNot(contains('PLACED')),
            reason: 'technical codes must not leak ($code)');
      }
    }
    // translations are genuinely different, not copies of Russian
    expect(const S(Locale('en')).navOrders,
        isNot(const S(Locale('ru')).navOrders));
    expect(const S(Locale('kk')).navOrders,
        isNot(const S(Locale('ru')).navOrders));
  });
}
