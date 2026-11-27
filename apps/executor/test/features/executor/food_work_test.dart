import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_localization/kunde_localizations.dart';
import 'package:kunde_executor/features/executor/food_work_screen.dart';
import 'package:kunde_auth/auth_repository.dart';
import 'package:kunde_design/kunde_theme.dart';

class _Vault implements TokenVault {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async {}
  @override
  Future<void> clear() async {}
}

class _Gateway implements OAuthGateway {
  @override
  Future<AuthTokens> login({bool register = false}) async => AuthTokens(
      'access',
      'refresh',
      null,
      DateTime.now().add(const Duration(minutes: 5)));
  @override
  Future<AuthTokens> refresh(String refreshToken) => login();
  @override
  Future<void> logout(String? idToken) async {}
}

/// In-memory courier backend: one open task, first accept wins, pickup then delivery.
class _Backend {
  _Backend({this.prefix = 'executor/food'});

  /// API prefix the screen under test is expected to call (`executor/food` or `executor/flowers`).
  final String prefix;
  String profileStatus = 'APPROVED';
  bool online = true;
  bool taken = false;
  String? taskStatus = 'OPEN';
  final calls = <String>[];

  Map<String, dynamic> task() => {
        'id': 't1',
        'shortRef': 'AB12CD34',
        'status': taskStatus,
        'storeName': 'Фреш Маркет',
        'storeAddress': 'пр. Абая 1',
        'deliveryAddress':
            taskStatus == 'OPEN' ? null : 'ул. Сатпаева 90, кв. 45',
        'comment': 'Позвонить у двери',
        'itemCount': 3,
        'totalMinor': 325000,
        'collectOnDelivery': true,
      };

  http.Response _json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status,
          headers: {'content-type': 'application/json; charset=utf-8'});

  Future<http.Response> handle(http.Request r) async {
    final path = r.url.path.replaceFirst('/api/v1/', '');
    calls.add('${r.method} $path');
    if (path == 'executor/deliveries/profile') {
      return _json(
          {'status': profileStatus, 'online': online, 'name': 'Курьер'});
    }
    if (path == 'executor/deliveries/availability') {
      online = (jsonDecode(r.body) as Map)['online'] as bool;
      return _json({'status': profileStatus, 'online': online});
    }
    if (path == '$prefix/tasks/open') {
      return _json(taskStatus == 'OPEN' ? [task()] : []);
    }
    if (path == '$prefix/tasks/mine') {
      return _json(taskStatus == 'OPEN' ? [] : [task()]);
    }
    if (path == '$prefix/tasks/t1/accept') {
      if (taken) return _json({'code': 'TASK_UNAVAILABLE'}, 409);
      taskStatus = 'ASSIGNED';
      return _json(task());
    }
    if (path == '$prefix/tasks/t1/pickup') {
      taskStatus = 'PICKED_UP';
      return _json(task());
    }
    if (path == '$prefix/tasks/t1/deliver') {
      taskStatus = 'DELIVERED';
      return _json(task());
    }
    return _json({'code': 'NOT_FOUND'}, 404);
  }
}

Future<AuthRepository> _auth(_Backend backend) async {
  final auth = AuthRepository(
    gateway: _Gateway(),
    vault: _Vault(),
    apiBase: Uri.parse('https://api.example.test/api/v1/'),
    client: MockClient(backend.handle),
  );
  await auth.signIn(AuthTokens('access', 'refresh', null,
      DateTime.now().add(const Duration(minutes: 5))));
  addTearDown(auth.dispose);
  return auth;
}

Future<void> _show(WidgetTester tester, Widget home,
    {double textScale = 1}) async {
  tester.view.physicalSize = const Size(1080, 2200);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: KundeTheme.light,
      locale: const Locale('ru'),
      supportedLocales: KundeLocalizations.supportedLocales,
      localizationsDelegates: KundeLocalizations.localizationsDelegates,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!),
      home: home));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('accept, collect, route and deliver a store order end to end',
      (tester) async {
    final backend = _Backend();
    final auth = await _auth(backend);
    final opened = <String>[];
    await _show(
        tester,
        FoodWorkScreen(
            auth: auth,
            openMap: (a) async {
              opened.add(a);
              return true;
            }));
    expect(find.textContaining('№ AB12CD34 · Фреш Маркет'), findsOneWidget);
    expect(find.text('Взять заказ'), findsOneWidget);
    // The customer's address is not shown before acceptance.
    expect(find.textContaining('Сатпаева'), findsNothing);

    await tester.tap(find.text('Взять заказ'));
    await tester.pumpAndSettle();
    expect(find.text('Забрать в магазине'), findsOneWidget);
    expect(find.text('пр. Абая 1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('food-route')));
    await tester.pumpAndSettle();
    expect(opened, ['пр. Абая 1']);

    await tester.tap(find.text('Забрал заказ'));
    await tester.pumpAndSettle();
    expect(find.text('Адрес доставки'), findsOneWidget);
    expect(find.text('ул. Сатпаева 90, кв. 45'), findsOneWidget);
    expect(find.textContaining('Получить наличными: 3 250 ₸'), findsOneWidget);
    await tester.tap(find.byKey(const Key('food-route')));
    await tester.pumpAndSettle();
    expect(opened.last, 'ул. Сатпаева 90, кв. 45');

    await tester.tap(find.text('Доставлено'));
    await tester.pumpAndSettle();
    expect(find.text('История'), findsOneWidget);
    expect(find.text('Доставлен'), findsOneWidget);
    expect(
        backend.calls
            .where((c) => c.startsWith('POST executor/food/tasks/t1/')),
        [
          'POST executor/food/tasks/t1/accept',
          'POST executor/food/tasks/t1/pickup',
          'POST executor/food/tasks/t1/deliver'
        ]);
  });

  testWidgets(
      'a task taken by another courier is explained and removed from the list',
      (tester) async {
    final backend = _Backend()..taken = true;
    final auth = await _auth(backend);
    await _show(tester, FoodWorkScreen(auth: auth, openMap: (_) async => true));
    await tester.tap(find.text('Взять заказ'));
    await tester.pumpAndSettle();
    expect(find.text('Заказ уже взял другой курьер'), findsOneWidget);
  });

  testWidgets('without a map app the address is copied as the fallback',
      (tester) async {
    final backend = _Backend()..taskStatus = 'ASSIGNED';
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    final auth = await _auth(backend);
    await _show(
        tester, FoodWorkScreen(auth: auth, openMap: (_) async => false));
    await tester.tap(find.byKey(const Key('food-route')));
    await tester.pumpAndSettle();
    expect(copied, 'пр. Абая 1');
    expect(find.text('Карты недоступны — адрес скопирован'), findsOneWidget);
  });

  testWidgets(
      'an unapproved courier is told what to do; going online is a server call',
      (tester) async {
    final backend = _Backend()..profileStatus = 'PENDING';
    final auth = await _auth(backend);
    await _show(tester, FoodWorkScreen(auth: auth, openMap: (_) async => true));
    expect(find.textContaining('Нужен одобренный профиль курьера'),
        findsOneWidget);
    expect(find.text('Взять заказ'), findsNothing);

    final approved = _Backend()..online = false;
    final auth2 = await _auth(approved);
    await _show(
        tester, FoodWorkScreen(auth: auth2, openMap: (_) async => true));
    expect(
        find.text('Включите «Онлайн», чтобы видеть заказы.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('food-online')));
    await tester.pumpAndSettle();
    expect(approved.online, isTrue);
    expect(find.text('Взять заказ'), findsOneWidget);
  });

  for (final width in [320.0, 360.0]) {
    testWidgets('the courier screen fits $width dp with 200% text',
        (tester) async {
      final backend = _Backend();
      final auth = await _auth(backend);
      tester.view.physicalSize = Size(width * 2.75, 2200);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
          theme: KundeTheme.light,
          locale: const Locale('ru'),
          supportedLocales: KundeLocalizations.supportedLocales,
          localizationsDelegates: KundeLocalizations.localizationsDelegates,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!),
          home: FoodWorkScreen(auth: auth, openMap: (_) async => true)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'the flowers variant calls the flowers endpoints and shows its own title',
      (tester) async {
    final backend = _Backend(prefix: 'executor/flowers');
    final auth = await _auth(backend);
    await _show(
        tester,
        FoodWorkScreen(
            auth: auth,
            basePath: 'executor/flowers',
            title: 'Заказы цветов',
            openMap: (_) async => true));
    expect(find.text('Заказы цветов'), findsOneWidget);
    await tester.tap(find.text('Взять заказ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Забрал заказ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Доставлено'));
    await tester.pumpAndSettle();
    expect(
        backend.calls.where((c) => c.startsWith('POST executor/flowers/tasks/t1/')),
        [
          'POST executor/flowers/tasks/t1/accept',
          'POST executor/flowers/tasks/t1/pickup',
          'POST executor/flowers/tasks/t1/deliver'
        ]);
    expect(backend.calls.where((c) => c.contains('executor/food')), isEmpty);
  });
}
