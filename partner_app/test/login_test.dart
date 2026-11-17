import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_partner/app/app.dart';
import 'package:kunde_partner/app/app_controller.dart';
import 'package:kunde_partner/app/settings.dart';
import 'package:kunde_partner/auth/partner_session.dart';

import 'support/fake_backend.dart';
import 'support/pump.dart';

void main() {
  testWidgets('starts at OTP login, not inside the workspace', (tester) async {
    final h = Harness(signedIn: false);
    await pumpLogin(tester, h);
    expect(find.text('Вход для партнёров'), findsOneWidget);
    expect(find.text('Получить код'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(h.backend.calls, isEmpty,
        reason: 'nothing is requested before sign-in');
  });

  testWidgets('validates the phone before any request', (tester) async {
    final h = Harness(signedIn: false);
    await pumpLogin(tester, h);
    await tester.enterText(find.byType(TextField), '123');
    await tester.tap(find.text('Получить код'));
    await tester.pump();
    expect(find.text('Введите номер в формате +7…'), findsOneWidget);
    expect(h.backend.calls, isEmpty);
  });

  testWidgets(
      'full OTP flow: wrong code is explained, right code opens the workspace',
      (tester) async {
    final h = Harness(signedIn: false);
    await pumpLogin(tester, h);
    await tester.enterText(find.byType(TextField), '8 700 000 00 02');
    await tester.tap(find.text('Получить код'));
    await settle(tester);
    expect(h.backend.calls, contains('POST auth/otp/request'));
    expect(find.text('Код отправлен на +77000000002'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, '000000');
    await tester.tap(find.text('Войти'));
    await settle(tester);
    expect(find.text('Неверный или просроченный код'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.tap(find.text('Войти'));
    await settle(tester, ms: 80);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Заказы'), findsWidgets);
  });

  testWidgets('shows a calm notice after the session expired', (tester) async {
    final h = Harness();
    await pumpReady(tester, h);
    h.controller.session.onExpired!.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Сессия истекла. Войдите снова.'), findsOneWidget);
  });

  testWidgets('unconfigured API address disables sign-in with an explanation',
      (tester) async {
    final session =
        PartnerSession(apiBase: Uri.parse(''), storage: MemoryStore());
    final controller = AppController(session: session, pollInterval: null);
    await tester.runAsync(controller.bootstrap);
    final settings = SettingsController(MemoryStore());
    await settings.setLocale(const Locale('ru'));
    await tester.pumpWidget(
        KundePartnerApp(controller: controller, settings: settings));
    await tester.pump();
    expect(find.textContaining('Адрес сервера не настроен'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });

  testWidgets(
      'without approved partner the user sees the no-access screen, never partner data',
      (tester) async {
    final b = FakeBackend()..partners = [];
    final h = Harness(backend: b);
    await pumpReady(tester, h);
    expect(find.text('Нет доступа к кабинету'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(
        b.calls.where((c) => c.contains('/food/') || c.contains('/booking/')),
        isEmpty);
  });

  testWidgets('several businesses: the user chooses one', (tester) async {
    final b = FakeBackend()
      ..partners = [
        {
          'id': 'p-a',
          'displayName': 'Первый салон',
          'verificationStatus': 'APPROVED',
          'role': 'MANAGER'
        },
        {
          'id': partnerId,
          'displayName': 'Второй ресторан',
          'verificationStatus': 'APPROVED',
          'role': 'OWNER'
        },
      ];
    final h = Harness(backend: b, store: storedSession());
    await pumpReady(tester, h);
    expect(find.text('Выберите заведение'), findsOneWidget);
    expect(find.text('Первый салон'), findsOneWidget);
    expect(find.text('Менеджер'), findsOneWidget);
    await tester.tap(find.text('Второй ресторан'));
    await settle(tester);
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
