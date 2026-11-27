import 'package:kunde_auth/auth_repository.dart';

import 'flowers_models.dart';

/// Why a flowers order call failed, in terms the screens can explain.
enum FlowersFailure {
  priceChanged,
  stock,
  slot,
  shopClosed,
  address,
  notCancellable,
  signedOut,
  other,
}

class FlowersException implements Exception {
  FlowersException(this.failure);

  final FlowersFailure failure;
}

/// Authenticated Flowers & Gifts cart and order calls (`/flowers/cart/quote`, `/flowers/orders`).
class FlowersOrdersApi {
  FlowersOrdersApi(this._auth);

  final AuthRepository _auth;

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on IdentityApiError catch (e) {
      throw FlowersException(switch ((e.status, e.code)) {
        (401, _) => FlowersFailure.signedOut,
        (_, 'FLOWERS_PRICE_CHANGED') => FlowersFailure.priceChanged,
        (_, 'FLOWERS_STOCK_INSUFFICIENT' || 'FLOWERS_PRODUCT_UNAVAILABLE') =>
          FlowersFailure.stock,
        (_, 'FLOWERS_SLOT_UNAVAILABLE' || 'FLOWERS_SLOT_REQUIRED') =>
          FlowersFailure.slot,
        (_, 'FLOWERS_SHOP_CLOSED') => FlowersFailure.shopClosed,
        (_, 'ADDRESS_REQUIRED') => FlowersFailure.address,
        (_, 'ORDER_NOT_CANCELLABLE') => FlowersFailure.notCancellable,
        _ => FlowersFailure.other,
      });
    } catch (_) {
      throw FlowersException(FlowersFailure.other);
    }
  }

  Future<FlowersQuote> quote({
    required String shopId,
    required List<Map<String, dynamic>> items,
    required String deliveryMode,
    String? scheduledFromIso,
  }) =>
      _guard(() async => FlowersQuote.fromJson(
              await _auth.authorizedJson('POST', 'flowers/cart/quote', body: {
            'shopId': shopId,
            'items': items,
            'deliveryMode': deliveryMode,
            if (scheduledFromIso != null) 'scheduledFrom': scheduledFromIso,
          }) as Map<String, dynamic>));

  Future<FlowersOrder> place({
    required String idempotencyKey,
    required String shopId,
    required List<Map<String, dynamic>> items,
    required String deliveryMode,
    String? scheduledFromIso,
    required String addressText,
    String? recipientName,
    String? cardText,
    String? comment,
    required int expectedTotalMinor,
  }) =>
      _guard(() async => FlowersOrder.fromJson(await _auth.authorizedJson(
            'POST',
            'flowers/orders',
            expected: const {200, 201},
            headers: {'Idempotency-Key': idempotencyKey},
            body: {
              'shopId': shopId,
              'items': items,
              'deliveryMode': deliveryMode,
              if (scheduledFromIso != null) 'scheduledFrom': scheduledFromIso,
              'addressLabel': '',
              'addressText': addressText,
              if (recipientName != null && recipientName.isNotEmpty)
                'recipientName': recipientName,
              if (cardText != null && cardText.isNotEmpty) 'cardText': cardText,
              if (comment != null && comment.isNotEmpty) 'comment': comment,
              'expectedTotalMinor': expectedTotalMinor,
            },
          ) as Map<String, dynamic>));

  Future<List<FlowersOrder>> orders() => _guard(() async => [
        for (final o in await _auth.authorizedJson('GET', 'flowers/orders')
            as List<dynamic>)
          FlowersOrder.fromJson(o as Map<String, dynamic>),
      ]);

  Future<FlowersOrder> order(String id) =>
      _guard(() async => FlowersOrder.fromJson(await _auth.authorizedJson(
          'GET', 'flowers/orders/$id') as Map<String, dynamic>));

  Future<FlowersOrder> cancel(String id) =>
      _guard(() async => FlowersOrder.fromJson(await _auth.authorizedJson(
          'POST', 'flowers/orders/$id/cancel') as Map<String, dynamic>));
}
