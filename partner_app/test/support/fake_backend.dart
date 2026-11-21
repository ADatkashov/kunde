import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_partner/app/app.dart';
import 'package:kunde_partner/app/app_controller.dart';
import 'package:kunde_partner/app/settings.dart';
import 'package:kunde_partner/auth/partner_session.dart';

final apiBase = Uri.parse('https://example.test/api/v1/');
const partnerId = '11111111-1111-1111-1111-111111111111';
const orderId = 'aaaaaaaa-0000-0000-0000-000000000001';
const bookingId = 'bbbbbbbb-0000-0000-0000-000000000001';

class MemoryStore implements SecureKeyValue {
  MemoryStore([Map<String, String>? seed]) : data = {...?seed};
  final Map<String, String> data;
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
  @override
  Future<void> delete(String key) async => data.remove(key);
}

MemoryStore storedSession({String? partner, String refresh = 'refresh-1'}) =>
    MemoryStore({
      'kunde.partner.session.v1': jsonEncode({
        'base': apiBase.toString(),
        'refresh': refresh,
        if (partner != null) 'partnerId': partner,
      }),
    });

Map<String, dynamic> orderEntry({
  String id = orderId,
  String status = 'PLACED',
  List<String> allowedNext = const ['ACCEPTED', 'CANCELLED'],
  DateTime? placedAt,
  bool withDeadline = true,
  String? cancelReason,
}) {
  final placed =
      placedAt ?? DateTime.now().subtract(const Duration(minutes: 1));
  return {
    'order': {
      'id': id,
      'restaurantId': 'rest-1',
      'restaurantName': 'Кухня партнёра',
      'status': status,
      'paymentMethod': 'CASH_ON_DELIVERY',
      'paymentStatus': 'PAY_ON_RECEIPT',
      'currency': 'KZT',
      'subtotalMinor': 360000,
      'deliveryFeeMinor': 50000,
      'totalMinor': 410000,
      'addressText': 'ул. Абая 10, кв. 5',
      'comment': 'Без лука',
      'placedAt': placed.toUtc().toIso8601String(),
      'items': [
        {
          'name': 'Лагман',
          'quantity': 2,
          'lineTotalMinor': 240000,
          'optionsText': 'Острый'
        },
        {'name': 'Чай', 'quantity': 1, 'lineTotalMinor': 120000},
      ],
      'timeline': [
        {
          'status': 'PLACED',
          'at': placed.toUtc().toIso8601String(),
          'actor': 'CUSTOMER'
        },
      ],
      'cancelReason': cancelReason,
    },
    'customerRef': 'abcd1234',
    'allowedNext': allowedNext,
    'respondBy': withDeadline && status == 'PLACED'
        ? placed.add(const Duration(minutes: 5)).toUtc().toIso8601String()
        : null,
  };
}

Map<String, dynamic> bookingJson({
  String id = bookingId,
  String status = 'PENDING',
  List<String> allowedActions = const ['CONFIRM', 'REJECT'],
  DateTime? startsAt,
  Map<String, dynamic> extra = const {},
}) {
  final start = startsAt ?? DateTime.now().add(const Duration(days: 1));
  return {
    'id': id,
    'venueId': 'venue-1',
    'venueName': 'Барбершоп партнёра',
    'category': 'BARBER',
    'serviceName': 'Стрижка',
    'durationMinutes': 45,
    'masterId': 'm1',
    'masterName': 'Алия',
    'startsAt': start.toUtc().toIso8601String(),
    'endsAt': start.add(const Duration(minutes: 45)).toUtc().toIso8601String(),
    'priceMinor': 500000,
    'currency': 'KZT',
    'status': status,
    'customerRef': 'abcd1234',
    'createdAt': DateTime.now().toUtc().toIso8601String(),
    'allowedActions': allowedActions,
    'timeline': [
      {
        'status': 'PENDING',
        'at': DateTime.now().toUtc().toIso8601String(),
        'actor': 'CUSTOMER'
      },
    ],
    ...extra,
  };
}

/// Scriptable in-memory backend behind a [MockClient].
class FakeBackend {
  FakeBackend() {
    partners = [
      {
        'id': partnerId,
        'displayName': 'Демо-партнёр',
        'verificationStatus': 'APPROVED',
        'version': 1,
        'role': 'OWNER'
      },
    ];
  }

  final List<String> calls = [];
  final List<Map<String, String>> headers = [];
  final List<(String, Map<String, dynamic>)> bodies = [];
  late List<Map<String, dynamic>> partners;
  List<Map<String, dynamic>> activeOrders = [orderEntry()];
  List<Map<String, dynamic>> historyOrders = [];
  List<Map<String, dynamic>> requests = [bookingJson()];
  List<Map<String, dynamic>> upcoming = [];
  List<Map<String, dynamic>> bookingHistory = [];
  List<Map<String, dynamic>> promotions = [];
  List<Map<String, dynamic>> restaurants = [
    {
      'id': 'rest-1',
      'name': 'Кухня партнёра',
      'vertical': 'FOOD',
      'open': true,
      'synthetic': true
    },
  ];
  List<Map<String, dynamic>> venues = [
    {
      'id': 'venue-1',
      'name': 'Барбершоп партнёра',
      'category': 'BARBER',
      'open': true
    },
  ];

  List<Map<String, dynamic>> timeOff = [];
  Map<String, dynamic>? lastBookingAction;

  List<Map<String, dynamic>> dishes = [
    {
      'id': 'dish-1',
      'name': 'Лагман',
      'section': 'Горячее',
      'sectionId': 'sec-1',
      'priceMinor': 120000,
      'available': true,
      'stockQty': null,
      'unit': 'шт',
      'description': 'Домашний'
    },
    {
      'id': 'dish-2',
      'name': 'Чай',
      'section': 'Напитки',
      'sectionId': 'sec-2',
      'priceMinor': 30000,
      'available': true,
      'stockQty': 5,
      'unit': 'шт',
      'description': null
    },
  ];
  List<Map<String, dynamic>> services = [
    {
      'id': 'svc-1',
      'name': 'Стрижка',
      'durationMinutes': 45,
      'priceMinor': 500000,
      'available': true
    },
  ];
  List<Map<String, dynamic>> masters = [
    {
      'id': 'm1',
      'name': 'Алия',
      'active': true,
      'hours': [
        {
          'day': 1,
          'from': '10:00',
          'to': '19:00',
          'breakFrom': '13:00',
          'breakTo': '14:00'
        },
        {
          'day': 2,
          'from': '10:00',
          'to': '19:00',
          'breakFrom': null,
          'breakTo': null
        },
      ],
    },
  ];

  /// Role the fake enforces on management endpoints (Owner/Manager only).
  bool operatorRole = false;

  /// Overrides: key `"METHOD path"` (path without base, with query).
  final Map<String, FutureOr<http.Response> Function(http.Request)> overrides =
      {};

  int refreshCount = 0;
  http.Response Function(http.Request)? tokenRefresh;

  http.Response json(Object? body, [int status = 200]) => http.Response.bytes(
        utf8.encode(jsonEncode(body)),
        status,
        // Like Spring: no charset on purpose.
        headers: {'content-type': 'application/json'},
      );

  http.Response error(int status, String code) =>
      json({'status': status, 'code': code, 'message': code}, status);

  Future<http.Response> _handle(http.Request r) async {
    final path = r.url.path.replaceFirst('/api/v1/', '');
    final key = '${r.method} $path${r.url.hasQuery ? '?${r.url.query}' : ''}';
    calls.add(key);
    headers.add(r.headers);
    if (r.body.isNotEmpty) {
      try {
        bodies.add((key, jsonDecode(r.body) as Map<String, dynamic>));
      } on FormatException {
        // not JSON
      }
    }
    final override = overrides[key] ?? overrides['${r.method} $path'];
    if (override != null) return await override(r);
    if (path == 'auth/token/refresh') {
      refreshCount++;
      if (tokenRefresh != null) return tokenRefresh!(r);
      return json({
        'accessToken': 'access-$refreshCount',
        'refreshToken': 'refresh-${refreshCount + 1}',
        'expiresIn': 900
      });
    }
    if (path == 'auth/otp/request') return json({});
    if (path == 'auth/otp/verify') {
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      if (body['code'] != '123456') return error(400, 'OTP_INVALID');
      return json({
        'accessToken': 'access-v',
        'refreshToken': 'refresh-v',
        'expiresIn': 900
      });
    }
    if (path == 'auth/logout') return json({});
    if (path == 'partner/partners') return json(partners);
    final root = 'partner/partners/$partnerId/';
    if (path.startsWith(root)) {
      final rest = path.substring(root.length);
      final scope = r.url.queryParameters['scope'];
      if (r.method == 'GET') {
        if (rest == 'food/orders') {
          return json(scope == 'history' ? historyOrders : activeOrders);
        }
        if (rest == 'booking/bookings') {
          return json(switch (scope) {
            'requests' => requests,
            'upcoming' => upcoming,
            _ => bookingHistory,
          });
        }
        if (rest == 'food/restaurants') return json(restaurants);
        if (rest == 'food/promotions') return json(promotions);
        if (rest == 'booking/venues') return json(venues);
      }
      final managed = _manage(r, rest);
      if (managed != null) return managed;
      final order = RegExp(r'food/orders/([^/]+)/status').firstMatch(rest);
      if (order != null && r.method == 'POST') {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        final status = body['status'] as String;
        return json(orderEntry(
          id: order.group(1)!,
          status: status,
          allowedNext: const [],
          cancelReason: body['reason'] as String?,
        ));
      }
      final booking =
          RegExp(r'booking/bookings/([^/]+)/action').firstMatch(rest);
      if (booking != null && r.method == 'POST') {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        lastBookingAction = body;
        final status = switch (body['action']) {
          'CONFIRM' => 'CONFIRMED',
          'CHECK_IN' => 'CHECKED_IN',
          'START' || 'PROPOSE_PRICE' => 'IN_PROGRESS',
          'NO_SHOW' => 'NO_SHOW',
          'COMPLETE' => 'COMPLETED',
          _ => 'CANCELLED',
        };
        return json(bookingJson(
            id: booking.group(1)!, status: status, allowedActions: const []));
      }
    }
    return error(404, 'NOT_FOUND');
  }

  http.Response? _manage(http.Request r, String rest) {
    Map<String, dynamic> body() => jsonDecode(r.body) as Map<String, dynamic>;
    final forbidden = error(403, 'PARTNER_ROLE_FORBIDDEN');
    if (r.method == 'GET') {
      if (RegExp(r'^food/restaurants/[^/]+/dishes$').hasMatch(rest)) {
        return json(dishes);
      }
      if (RegExp(r'^booking/venues/[^/]+/services$').hasMatch(rest)) {
        return json(services);
      }
      if (RegExp(r'^booking/venues/[^/]+/masters$').hasMatch(rest)) {
        return json(masters);
      }
      if (RegExp(r'^booking/venues/[^/]+/time-off$').hasMatch(rest)) {
        return json(timeOff);
      }
      return null;
    }
    if (RegExp(r'^booking/venues/[^/]+/time-off$').hasMatch(rest) &&
        r.method == 'POST') {
      if (operatorRole) return forbidden;
      final created = {'id': 'off-${timeOff.length + 1}', ...body()};
      timeOff = [...timeOff, created];
      return json(created);
    }
    var off =
        RegExp(r'^booking/venues/[^/]+/time-off/([^/]+)$').firstMatch(rest);
    if (off != null && r.method == 'DELETE') {
      timeOff = [
        for (final t in timeOff)
          if (t['id'] != off.group(1)) t
      ];
      return http.Response('', 204);
    }
    if (RegExp(r'^booking/venues/[^/]+/services$').hasMatch(rest) &&
        r.method == 'POST') {
      if (operatorRole) return forbidden;
      final created = {
        'id': 'svc-new',
        'available': true,
        'priceKind': 'FIXED',
        'conditions': '',
        ...body()
      };
      services = [...services, created];
      return json(created);
    }
    if (RegExp(r'^booking/venues/[^/]+/masters$').hasMatch(rest) &&
        r.method == 'POST') {
      if (operatorRole) return forbidden;
      final created = {
        'id': 'post-new',
        'active': true,
        'hours': [],
        'name': body()['name']
      };
      masters = [...masters, created];
      return json(created);
    }
    var svc =
        RegExp(r'^booking/venues/[^/]+/services/([^/]+)$').firstMatch(rest);
    if (svc != null && r.method == 'PUT') {
      if (operatorRole) return forbidden;
      services = [
        for (final x in services)
          x['id'] == svc.group(1) ? {...x, ...body()} : x
      ];
      return json(services.firstWhere((x) => x['id'] == svc.group(1)));
    }
    if (rest == 'food/promotions' && r.method == 'POST') {
      if (operatorRole) return forbidden;
      final b = body();
      final created = {
        'id': 'promo-${promotions.length + 1}',
        'status': 'ACTIVE',
        'redeemed': 0,
        ...b,
      };
      promotions = [created, ...promotions];
      return json(created);
    }
    final promoStatus =
        RegExp(r'^food/promotions/([^/]+)/status$').firstMatch(rest);
    if (promoStatus != null && r.method == 'POST') {
      promotions = [
        for (final x in promotions)
          x['id'] == promoStatus.group(1)
              ? {...x, 'status': body()['status']}
              : x
      ];
      return json(
          promotions.firstWhere((x) => x['id'] == promoStatus.group(1)));
    }
    var m = RegExp(r'^food/restaurants/([^/]+)$').firstMatch(rest);
    if (m != null && r.method == 'PATCH') {
      if (operatorRole) return forbidden;
      restaurants = [
        for (final x in restaurants)
          x['id'] == m.group(1) ? {...x, ...body()} : x
      ];
      return json(restaurants.firstWhere((x) => x['id'] == m!.group(1)));
    }
    m = RegExp(r'^food/restaurants/([^/]+)/dishes/([^/]+)$').firstMatch(rest);
    if (m != null && r.method == 'PATCH') {
      final b = body();
      if (operatorRole &&
          (b.containsKey('name') ||
              b.containsKey('priceMinor') ||
              b.containsKey('description'))) {
        return forbidden;
      }
      dishes = [
        for (final d in dishes)
          d['id'] == m.group(2)
              ? {
                  ...d,
                  if (b.containsKey('available')) 'available': b['available'],
                  if (b.containsKey('name')) 'name': b['name'],
                  if (b.containsKey('priceMinor'))
                    'priceMinor': b['priceMinor'],
                  if (b.containsKey('stockQty')) 'stockQty': b['stockQty'],
                  if (b['clearStock'] == true) 'stockQty': null,
                }
              : d,
      ];
      return json(dishes.firstWhere((d) => d['id'] == m!.group(2)));
    }
    m = RegExp(r'^food/restaurants/([^/]+)/dishes$').firstMatch(rest);
    if (m != null && r.method == 'POST') {
      if (operatorRole) return forbidden;
      final b = body();
      final created = {
        'id': 'dish-new',
        'name': b['name'],
        'section': 'Горячее',
        'sectionId': b['sectionId'],
        'priceMinor': b['priceMinor'],
        'available': true,
        'stockQty': null
      };
      dishes = [...dishes, created];
      return json(created, 201);
    }
    m = RegExp(r'^booking/venues/([^/]+)$').firstMatch(rest);
    if (m != null && r.method == 'PATCH') {
      if (operatorRole) return forbidden;
      venues = [
        for (final x in venues)
          x['id'] == m.group(1) ? {...x, 'open': body()['open']} : x
      ];
      return json(venues.firstWhere((x) => x['id'] == m!.group(1)));
    }
    m = RegExp(r'^booking/venues/([^/]+)/services/([^/]+)$').firstMatch(rest);
    if (m != null && r.method == 'PATCH') {
      services = [
        for (final x in services)
          x['id'] == m.group(2) ? {...x, 'available': body()['available']} : x
      ];
      return json(services.firstWhere((x) => x['id'] == m!.group(2)));
    }
    m = RegExp(r'^booking/venues/([^/]+)/masters/([^/]+)$').firstMatch(rest);
    if (m != null && r.method == 'PATCH') {
      masters = [
        for (final x in masters)
          x['id'] == m.group(2) ? {...x, 'active': body()['active']} : x
      ];
      return json(masters.firstWhere((x) => x['id'] == m!.group(2)));
    }
    m = RegExp(r'^booking/venues/([^/]+)/masters/([^/]+)/hours$')
        .firstMatch(rest);
    if (m != null && r.method == 'PUT') {
      if (operatorRole) return forbidden;
      masters = [
        for (final x in masters)
          x['id'] == m.group(2) ? {...x, 'hours': body()['hours']} : x
      ];
      return json(masters.firstWhere((x) => x['id'] == m!.group(2)));
    }
    return null;
  }

  MockClient get client => MockClient(_handle);

  int count(String prefix) => calls.where((c) => c.startsWith(prefix)).length;
}

/// A fully wired app around a [FakeBackend].
class Harness {
  Harness._(this.backend, this.controller, this.settings, this.store);

  factory Harness({
    FakeBackend? backend,
    MemoryStore? store,
    bool signedIn = true,
    Locale? locale,
  }) {
    final b = backend ?? FakeBackend();
    final mem =
        store ?? (signedIn ? storedSession(partner: partnerId) : MemoryStore());
    final session = PartnerSession(
      apiBase: apiBase,
      client: b.client,
      storage: mem,
      timeout: const Duration(seconds: 5),
    );
    final controller = AppController(
        session: session,
        client: b.client,
        pollInterval: null,
        retryDelay: Duration.zero);
    final settings = SettingsController(MemoryStore());
    settings.setLocale(locale ?? const Locale('ru'));
    return Harness._(b, controller, settings, mem);
  }

  final FakeBackend backend;
  final AppController controller;
  final SettingsController settings;
  final MemoryStore store;

  Widget get app => KundePartnerApp(controller: controller, settings: settings);
}
