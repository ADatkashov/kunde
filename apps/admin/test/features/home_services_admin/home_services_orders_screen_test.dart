import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_admin/features/home_services_admin/home_services_orders_screen.dart';
import 'package:kunde_auth/auth_repository.dart';

Map<String, dynamic> _row(String id, String status) => {
      'id': id,
      'bookingNumber': 'KND-100001',
      'serviceName': 'Генеральная уборка',
      'venueName': 'Clean Co',
      'masterName': 'Бригада «Север»',
      'status': status,
      'stage': null,
      'startsAt': '2026-12-01T10:00:00Z',
      'priceMinor': 1500000,
      'createdAt': '2026-11-28T08:00:00Z',
      'cancelledBy': null,
    };

class _Session implements AuthRepository {
  _Session({this.status = 'CONFIRMED', this.failActions = false});

  final String status;
  final bool failActions;
  final calls = <String>[];
  final posts = <String, Map<String, dynamic>?>{};

  @override
  Future<dynamic> authorizedJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Set<int> expected = const {200},
    Map<String, String>? headers,
  }) async {
    calls.add('$method $path');
    if (method == 'POST') {
      if (failActions) throw Exception('conflict');
      posts[path] = body;
      return <String, dynamic>{};
    }
    if (path.endsWith('/masters')) {
      return [
        {'id': 'm1', 'name': 'Бригада «Север»', 'online': true},
        {'id': 'm2', 'name': 'Бригада «Юг»', 'online': true},
      ];
    }
    if (path.startsWith('admin/home-services/orders/')) {
      final actionable = status == 'PENDING' || status == 'CONFIRMED';
      return {
        'order': _row('o1', status),
        'addressText': 'Алматы, ул. Абая 150',
        'areaSqm': 50,
        'comment': null,
        'cancelReason': null,
        'version': 3,
        'actionable': actionable,
        'visit': null,
        'history': [
          {
            'status': 'CONFIRMED',
            'actorType': 'PARTNER',
            'reason': null,
            'occurredAt': '2026-11-28T09:00:00Z',
          },
        ],
        'adminActions': [
          {
            'action': 'REASSIGN',
            'reason': 'Мастер заболел',
            'occurredAt': '2026-11-28T10:00:00Z',
          },
        ],
      };
    }
    final onlyCancelled = path.contains('status=CANCELLED');
    return {
      'items': onlyCancelled ? <Map<String, dynamic>>[] : [_row('o1', status)],
      'total': onlyCancelled ? 0 : 1,
      'limit': 30,
      'offset': 0,
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('money is shown in tenge from minor units', () {
    expect(formatTenge(1500000), '15 000 ₸');
    expect(formatTenge(800000), '8 000 ₸');
    expect(formatTenge(0), '0 ₸');
    expect(formatTenge(123456700), '1 234 567 ₸');
  });

  testWidgets('register lists orders without customer data and filters',
      (tester) async {
    final auth = _Session();
    await tester.pumpWidget(
      MaterialApp(home: HomeServicesOrdersScreen(auth: auth)),
    );
    await tester.pumpAndSettle();

    expect(find.text('KND-100001 · Генеральная уборка'), findsOneWidget);
    expect(find.textContaining('15 000 ₸'), findsOneWidget);
    expect(find.text('Found: 1'), findsOneWidget);
    expect(
        auth.calls.first, 'GET admin/home-services/orders?limit=30&offset=0');

    await tester.ensureVisible(find.byKey(const ValueKey('status-CANCELLED')));
    await tester.tap(find.byKey(const ValueKey('status-CANCELLED')));
    await tester.pumpAndSettle();
    expect(find.text('No orders'), findsOneWidget);
    expect(
      auth.calls.last,
      'GET admin/home-services/orders?status=CANCELLED&limit=30&offset=0',
    );

    await tester.enterText(
        find.byKey(const ValueKey('order-search')), 'knd-1000');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(
      auth.calls.last,
      'GET admin/home-services/orders?status=CANCELLED&q=knd-1000&limit=30&offset=0',
    );
  });

  testWidgets('a failed register load offers a retry', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: HomeServicesOrdersScreen(auth: _FailingSession()),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(TextButton), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('cancel needs a reason and sends the version the screen saw',
      (tester) async {
    final auth = _Session();
    await tester.pumpWidget(MaterialApp(
      home: HomeServicesOrderScreen(auth: auth, orderId: 'o1'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Алматы, ул. Абая 150'), findsOneWidget);
    expect(find.byKey(const ValueKey('admin-action-REASSIGN')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cancel')));
    await tester.pumpAndSettle();
    final confirm = find.byKey(const ValueKey('confirm'));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.enterText(find.byKey(const ValueKey('reason')), 'по просьбе');
    await tester.pump();
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(auth.posts['admin/home-services/orders/o1/cancel'], {
      'expectedVersion': 3,
      'reason': 'по просьбе',
    });
    // The card is reloaded after the action.
    expect(
      auth.calls.where((c) => c == 'GET admin/home-services/orders/o1'),
      hasLength(2),
    );
  });

  testWidgets('reassign offers the other masters of the venue only',
      (tester) async {
    final auth = _Session();
    await tester.pumpWidget(MaterialApp(
      home: HomeServicesOrderScreen(auth: auth, orderId: 'o1'),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('reassign')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('master-m1')), findsNothing);
    final confirm = find.byKey(const ValueKey('confirm'));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('master-m2')));
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.enterText(find.byKey(const ValueKey('reason')), 'заболел');
    await tester.pump();
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(auth.posts['admin/home-services/orders/o1/reassign'], {
      'masterId': 'm2',
      'expectedVersion': 3,
      'reason': 'заболел',
    });
  });

  testWidgets('work that has started offers no actions', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: HomeServicesOrderScreen(
        auth: _Session(status: 'IN_PROGRESS'),
        orderId: 'o1',
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cancel')), findsNothing);
    expect(find.byKey(const ValueKey('reassign')), findsNothing);
  });

  testWidgets('a rejected action shows a message and reloads the card',
      (tester) async {
    final auth = _Session(failActions: true);
    await tester.pumpWidget(MaterialApp(
      home: HomeServicesOrderScreen(auth: auth, orderId: 'o1'),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cancel')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('reason')), 'причина');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('confirm')));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      auth.calls.where((c) => c == 'GET admin/home-services/orders/o1'),
      hasLength(2),
    );
  });
}

class _FailingSession implements AuthRepository {
  @override
  Future<dynamic> authorizedJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Set<int> expected = const {200},
    Map<String, String>? headers,
  }) async =>
      throw Exception('offline');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
