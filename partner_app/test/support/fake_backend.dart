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
  late List<Map<String, dynamic>> partners;
  List<Map<String, dynamic>> activeOrders = [orderEntry()];
  List<Map<String, dynamic>> historyOrders = [];
  List<Map<String, dynamic>> requests = [bookingJson()];
  List<Map<String, dynamic>> upcoming = [];
  List<Map<String, dynamic>> bookingHistory = [];
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
        if (rest == 'food/orders')
          return json(scope == 'history' ? historyOrders : activeOrders);
        if (rest == 'booking/bookings') {
          return json(switch (scope) {
            'requests' => requests,
            'upcoming' => upcoming,
            _ => bookingHistory,
          });
        }
        if (rest == 'food/restaurants') return json(restaurants);
        if (rest == 'booking/venues') return json(venues);
      }
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
        final status = switch (body['action']) {
          'CONFIRM' => 'CONFIRMED',
          'COMPLETE' => 'COMPLETED',
          _ => 'CANCELLED',
        };
        return json(bookingJson(
            id: booking.group(1)!, status: status, allowedActions: const []));
      }
    }
    return error(404, 'NOT_FOUND');
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
