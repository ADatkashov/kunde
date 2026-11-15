import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../../identity/auth_repository.dart';
import 'food_models.dart';

/// Why a Food call failed, in terms the UI can explain in Russian.
enum FoodFailure {
  offline,
  sessionExpired,
  minOrder,
  closed,
  itemUnavailable,
  optionsInvalid,
  addressMissing,
  tooManyOrders,
  notCancellable,
  notFound,
  other,
}

class FoodException implements Exception {
  const FoodException(this.failure);

  final FoodFailure failure;

  String get message => switch (failure) {
        FoodFailure.offline =>
          'Нет связи с сервером. Проверьте интернет и попробуйте снова.',
        FoodFailure.sessionExpired => 'Сессия истекла. Войдите снова.',
        FoodFailure.minOrder =>
          'Сумма заказа меньше минимальной для этого ресторана.',
        FoodFailure.closed => 'Ресторан сейчас закрыт.',
        FoodFailure.itemUnavailable =>
          'Одно из блюд больше недоступно. Обновите корзину.',
        FoodFailure.optionsInvalid =>
          'Выбор опций блюда устарел. Удалите блюдо и добавьте снова.',
        FoodFailure.addressMissing => 'Выберите адрес доставки.',
        FoodFailure.tooManyOrders =>
          'Слишком много активных заказов. Дождитесь доставки.',
        FoodFailure.notCancellable =>
          'Ресторан уже принял заказ — отмена недоступна.',
        FoodFailure.notFound => 'Не найдено.',
        FoodFailure.other => 'Не удалось выполнить действие. Попробуйте позже.',
      };
}

class CheckoutRequest {
  const CheckoutRequest({
    required this.restaurantId,
    required this.items,
    required this.addressId,
    required this.paymentMethod,
    this.comment,
  });

  final String restaurantId;
  final List<Map<String, dynamic>> items;
  final String addressId;

  /// `TEST_CARD` (DEV mock, no card data) or `CASH_ON_DELIVERY`.
  final String paymentMethod;
  final String? comment;
}

/// KUNDE Food client: public catalog over plain HTTP, cart/orders through the authenticated repository.
class FoodApi {
  FoodApi({
    required Uri baseUri,
    required this.auth,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  })  : _base = baseUri.toString().endsWith('/')
            ? baseUri
            : baseUri.replace(path: '${baseUri.path}/'),
        _client = client ?? http.Client();

  final Uri _base;
  final http.Client _client;
  final AuthRepository auth;
  final Duration timeout;

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on FoodException {
      rethrow;
    } on SessionExpired {
      throw const FoodException(FoodFailure.sessionExpired);
    } on IdentityApiError catch (error) {
      throw FoodException(_map(error));
    } on TimeoutException {
      throw const FoodException(FoodFailure.offline);
    } on IdentityUnavailable {
      throw const FoodException(FoodFailure.offline);
    } on http.ClientException {
      throw const FoodException(FoodFailure.offline);
    } on FormatException {
      throw const FoodException(FoodFailure.other);
    } on TypeError {
      throw const FoodException(FoodFailure.other);
    }
  }

  static FoodFailure _map(IdentityApiError error) => switch (error.code) {
        'FOOD_MIN_ORDER_NOT_MET' => FoodFailure.minOrder,
        'RESTAURANT_CLOSED' => FoodFailure.closed,
        'FOOD_ITEM_UNAVAILABLE' => FoodFailure.itemUnavailable,
        'FOOD_OPTIONS_INVALID' => FoodFailure.optionsInvalid,
        'ADDRESS_NOT_FOUND' => FoodFailure.addressMissing,
        'TOO_MANY_ACTIVE_ORDERS' => FoodFailure.tooManyOrders,
        'ORDER_NOT_CANCELLABLE' => FoodFailure.notCancellable,
        'ORDER_NOT_FOUND' || 'RESTAURANT_NOT_FOUND' => FoodFailure.notFound,
        _ => error.status == 404 ? FoodFailure.notFound : FoodFailure.other,
      };

  Future<dynamic> _public(String path, [Map<String, String>? query]) =>
      _guard(() async {
        final uri = _base.resolve(path).replace(queryParameters: query);
        final response = await _client
            .get(uri, headers: {'Accept': 'application/json'}).timeout(timeout);
        if (response.statusCode == 404) {
          throw const FoodException(FoodFailure.notFound);
        }
        if (response.statusCode != 200) {
          throw const FoodException(FoodFailure.other);
        }
        return jsonDecode(utf8.decode(response.bodyBytes));
      });

  Future<List<Restaurant>> restaurants({String vertical = 'FOOD'}) async =>
      ((await _public('food/restaurants', {'vertical': vertical}))
              as List<dynamic>)
          .map((e) => Restaurant.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);

  Future<RestaurantMenu> menu(String restaurantId) async =>
      RestaurantMenu.fromJson((await _public('food/restaurants/$restaurantId'))
          as Map<String, dynamic>);

  Future<FoodSearchResult> search(String query,
          {String vertical = 'FOOD'}) async =>
      FoodSearchResult.fromJson(
          (await _public('food/search', {'q': query, 'vertical': vertical}))
              as Map<String, dynamic>);

  Future<FoodQuote> quote(
          String restaurantId, List<Map<String, dynamic>> items) =>
      _guard(() async {
        final json = await auth.authorizedJson('POST', 'food/cart/quote',
            body: {'restaurantId': restaurantId, 'items': items});
        return FoodQuote.fromJson(json as Map<String, dynamic>);
      });

  /// Idempotency-Key is generated once per checkout attempt by the caller so a retry never duplicates the order.
  Future<FoodOrder> placeOrder(
          CheckoutRequest request, String idempotencyKey) =>
      _guard(() async {
        final json = await auth.authorizedJson('POST', 'food/orders', body: {
          'restaurantId': request.restaurantId,
          'items': request.items,
          'addressId': request.addressId,
          'paymentMethod': request.paymentMethod,
          if (request.comment != null && request.comment!.trim().isNotEmpty)
            'comment': request.comment!.trim(),
        }, expected: const {
          200,
          201
        }, headers: {
          'Idempotency-Key': idempotencyKey
        });
        return FoodOrder.fromJson(json as Map<String, dynamic>);
      });

  Future<List<FoodOrder>> orders() => _guard(() async {
        final json = await auth.authorizedJson('GET', 'food/orders');
        return (json as List<dynamic>)
            .map((e) => FoodOrder.fromJson(e as Map<String, dynamic>))
            .toList(growable: false);
      });

  Future<FoodOrder> order(String id) => _guard(() async => FoodOrder.fromJson(
      (await auth.authorizedJson('GET', 'food/orders/$id'))
          as Map<String, dynamic>));

  Future<FoodOrder> cancel(String id) => _guard(() async => FoodOrder.fromJson(
      (await auth.authorizedJson('POST', 'food/orders/$id/cancel'))
          as Map<String, dynamic>));

  Future<RepeatResult> repeat(String id) =>
      _guard(() async => RepeatResult.fromJson((await auth.authorizedJson(
          'GET', 'food/orders/$id/repeat')) as Map<String, dynamic>));

  static String newIdempotencyKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return 'app-${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  }

  void close() => _client.close();
}
