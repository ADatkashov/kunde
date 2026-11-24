import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:kunde_auth/auth_repository.dart';
import 'groceries_models.dart';

enum GroceriesFailure {
  offline,
  sessionExpired,
  disabled,
  notFound,
  quantity,
  limit,
  storeConflict,
  nothingToAdd,
  reviewNotAllowed,
  other,
}

class GroceriesException implements Exception {
  const GroceriesException(this.failure);

  final GroceriesFailure failure;

  String messageFor(String language) {
    const ru = {
      GroceriesFailure.offline:
          'Нет связи с сервером. Проверьте интернет и попробуйте снова.',
      GroceriesFailure.sessionExpired: 'Сессия истекла. Войдите снова.',
      GroceriesFailure.disabled: 'Продукты сейчас недоступны.',
      GroceriesFailure.notFound: 'Товар не найден или больше недоступен.',
      GroceriesFailure.quantity:
          'Недопустимое количество: вес — шагом 100 г, штуки — до 20.',
      GroceriesFailure.limit: 'Достигнут лимит. Удалите что-нибудь ненужное.',
      GroceriesFailure.storeConflict: 'В корзине уже товары другого магазина.',
      GroceriesFailure.nothingToAdd:
          'В списке нет доступных товаров для корзины.',
      GroceriesFailure.reviewNotAllowed:
          'Отзыв можно оставить после доставки заказа с этим товаром.',
      GroceriesFailure.other:
          'Не удалось выполнить действие. Попробуйте позже.',
    };
    const kk = {
      GroceriesFailure.offline: 'Интернет байланысы жоқ. Қайталап көріңіз.',
      GroceriesFailure.sessionExpired: 'Сеанс аяқталды. Қайта кіріңіз.',
      GroceriesFailure.disabled: 'Азық-түлік қазір қолжетімсіз.',
      GroceriesFailure.notFound: 'Тауар табылмады немесе қолжетімсіз.',
      GroceriesFailure.quantity:
          'Сан дұрыс емес: салмақ 100 г қадаммен, дана — 20-ға дейін.',
      GroceriesFailure.limit: 'Шек толды. Артығын жойыңыз.',
      GroceriesFailure.storeConflict: 'Себетте басқа дүкеннің тауарлары бар.',
      GroceriesFailure.nothingToAdd: 'Тізімде себетке қосатын тауар жоқ.',
      GroceriesFailure.reviewNotAllowed:
          'Пікірді осы тауар бар тапсырыс жеткізілгеннен кейін қалдыруға болады.',
      GroceriesFailure.other: 'Әрекет орындалмады. Кейінірек көріңіз.',
    };
    const en = {
      GroceriesFailure.offline: 'No connection. Check your internet and retry.',
      GroceriesFailure.sessionExpired: 'Your session expired. Sign in again.',
      GroceriesFailure.disabled: 'Groceries is unavailable right now.',
      GroceriesFailure.notFound: 'The product was not found or is unavailable.',
      GroceriesFailure.quantity:
          'Invalid quantity: weight in 100 g steps, pieces up to 20.',
      GroceriesFailure.limit:
          'Limit reached. Remove something you do not need.',
      GroceriesFailure.storeConflict:
          'The cart already holds items from another store.',
      GroceriesFailure.nothingToAdd:
          'The list has no available items for the cart.',
      GroceriesFailure.reviewNotAllowed:
          'You can review a product after an order containing it is delivered.',
      GroceriesFailure.other: 'The action failed. Please try again later.',
    };
    return (switch (language) { 'kk' => kk, 'en' => en, _ => ru })[failure]!;
  }

  @override
  String toString() => 'GroceriesException($failure)';
}

/// KUNDE Groceries client: public catalog over plain HTTP, favorites, lists and the cart through the authenticated
/// repository. Everything the user owns lives on the server and follows the account across sessions.
class GroceriesApi {
  GroceriesApi({
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
    } on GroceriesException {
      rethrow;
    } on SessionExpired {
      throw const GroceriesException(GroceriesFailure.sessionExpired);
    } on IdentityApiError catch (error) {
      throw GroceriesException(_map(error));
    } on TimeoutException {
      throw const GroceriesException(GroceriesFailure.offline);
    } on IdentityUnavailable {
      throw const GroceriesException(GroceriesFailure.offline);
    } on http.ClientException {
      throw const GroceriesException(GroceriesFailure.offline);
    } on FormatException {
      throw const GroceriesException(GroceriesFailure.other);
    } on TypeError {
      throw const GroceriesException(GroceriesFailure.other);
    }
  }

  static GroceriesFailure _map(IdentityApiError error) => switch (error.code) {
        'GROCERIES_DISABLED' => GroceriesFailure.disabled,
        'PRODUCT_NOT_FOUND' ||
        'LIST_NOT_FOUND' ||
        'STORE_NOT_FOUND' =>
          GroceriesFailure.notFound,
        'QUANTITY_INVALID' => GroceriesFailure.quantity,
        'FAVORITES_LIMIT' ||
        'LISTS_LIMIT' ||
        'LIST_FULL' =>
          GroceriesFailure.limit,
        'CART_STORE_CONFLICT' => GroceriesFailure.storeConflict,
        'LIST_NOTHING_TO_ADD' => GroceriesFailure.nothingToAdd,
        'REVIEW_NOT_ALLOWED' => GroceriesFailure.reviewNotAllowed,
        _ => error.status == 404
            ? GroceriesFailure.notFound
            : GroceriesFailure.other,
      };

  Future<dynamic> _public(String path, [Map<String, String>? query]) =>
      _guard(() async {
        final uri = _base.resolve(path).replace(queryParameters: query);
        final response = await _client
            .get(uri, headers: {'Accept': 'application/json'}).timeout(timeout);
        if (response.statusCode == 404) {
          throw const GroceriesException(GroceriesFailure.notFound);
        }
        if (response.statusCode == 409) {
          throw const GroceriesException(GroceriesFailure.disabled);
        }
        if (response.statusCode != 200) {
          throw const GroceriesException(GroceriesFailure.other);
        }
        return jsonDecode(utf8.decode(response.bodyBytes));
      });

  Future<dynamic> _auth(String method, String path,
          {Map<String, dynamic>? body, Set<int> expected = const {200}}) =>
      _guard(() =>
          auth.authorizedJson(method, path, body: body, expected: expected));

  // ---- catalog ---------------------------------------------------------------------------------------

  Future<List<GroceryCategory>> categories() async =>
      ((await _public('groceries/categories')) as List<dynamic>)
          .map((e) => GroceryCategory.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);

  Future<List<String>> brands({String? category, String? storeId}) async =>
      ((await _public('groceries/brands', {
        if (category != null) 'category': category,
        if (storeId != null) 'storeId': storeId,
      })) as List<dynamic>)
          .cast<String>();

  Future<ProductsPage> products(ProductQuery query,
          {int limit = 30, int offset = 0}) async =>
      ProductsPage.fromJson((await _public('groceries/products',
              query.toQuery(limit: limit, offset: offset)))
          as Map<String, dynamic>);

  Future<ProductDetail> product(String id) async => ProductDetail.fromJson(
      (await _public('groceries/products/$id')) as Map<String, dynamic>);

  Future<ProductReviews> reviews(
          String productId) async =>
      ProductReviews.fromJson(
          (await _public('groceries/products/$productId/reviews'))
              as Map<String, dynamic>);

  /// True when the signed-in customer has a delivered order with this product and has not reviewed it yet.
  Future<bool> canReview(String productId) async =>
      ((await _auth('GET', 'groceries/products/$productId/review-eligibility'))
          as Map<String, dynamic>)['canReview'] ==
      true;

  Future<void> submitReview(String productId, int rating, String? comment) =>
      _auth('POST', 'groceries/products/$productId/reviews', body: {
        'rating': rating,
        if (comment != null && comment.trim().isNotEmpty)
          'comment': comment.trim(),
      }, expected: const {
        201
      });

  // ---- favorites -------------------------------------------------------------------------------------

  Future<List<GroceryProduct>> favorites() async =>
      ((await _auth('GET', 'groceries/favorites')) as List<dynamic>)
          .map((e) => GroceryProduct.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);

  Future<Set<String>> favoriteIds() async =>
      ((await _auth('GET', 'groceries/favorites/ids')) as List<dynamic>)
          .cast<String>()
          .toSet();

  Future<void> setFavorite(String productId, bool favorite) =>
      _auth(favorite ? 'PUT' : 'DELETE', 'groceries/favorites/$productId');

  // ---- shopping lists --------------------------------------------------------------------------------

  Future<List<GroceryListSummary>> lists() async =>
      ((await _auth('GET', 'groceries/lists')) as List<dynamic>)
          .map((e) => GroceryListSummary.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);

  Future<GroceryListSummary> createList(String name) async =>
      GroceryListSummary.fromJson((await _auth('POST', 'groceries/lists',
          body: {'name': name},
          expected: const {201})) as Map<String, dynamic>);

  Future<void> renameList(String id, String name) =>
      _auth('PUT', 'groceries/lists/$id', body: {'name': name});

  Future<void> deleteList(String id) =>
      _auth('DELETE', 'groceries/lists/$id', expected: const {204});

  Future<GroceryListDetail> list(String id) async => GroceryListDetail.fromJson(
      (await _auth('GET', 'groceries/lists/$id')) as Map<String, dynamic>);

  Future<GroceryListDetail> putListItem(String listId, String productId,
          {required int quantity, bool? checked}) async =>
      GroceryListDetail.fromJson((await _auth(
          'PUT', 'groceries/lists/$listId/items/$productId',
          body: {
            'quantity': quantity,
            if (checked != null) 'checked': checked,
          })) as Map<String, dynamic>);

  Future<GroceryListDetail> removeListItem(
          String listId, String productId) async =>
      GroceryListDetail.fromJson(
          (await _auth('DELETE', 'groceries/lists/$listId/items/$productId'))
              as Map<String, dynamic>);

  /// Moves available, not yet bought items to the server cart; returns what was skipped and why.
  Future<({ServerCart cart, List<SkippedItem> skipped})> listToCart(
      String listId,
      {String? storeId,
      bool replace = false}) async {
    final query = [
      if (storeId != null) 'storeId=$storeId',
      if (replace) 'replace=true',
    ].join('&');
    final json = (await _auth('POST',
            'groceries/lists/$listId/to-cart${query.isEmpty ? '' : '?$query'}'))
        as Map<String, dynamic>;
    return (
      cart: ServerCart.fromJson(json['cart'] as Map<String, dynamic>),
      skipped: ((json['skipped'] as List<dynamic>?) ?? const [])
          .map((e) => e as Map<String, dynamic>)
          .map((e) => SkippedItem(e['productId'] as String, e['name'] as String,
              e['reason'] as String))
          .toList(growable: false),
    );
  }

  // ---- cart ------------------------------------------------------------------------------------------

  Future<ServerCart> cart() async => ServerCart.fromJson(
      (await _auth('GET', 'groceries/cart')) as Map<String, dynamic>);

  /// Replaces the whole server cart; an empty [items] list clears it.
  Future<ServerCart> saveCart(
          String restaurantId, List<Map<String, dynamic>> items) async =>
      ServerCart.fromJson((await _auth('PUT', 'groceries/cart',
              body: {'restaurantId': restaurantId, 'items': items}))
          as Map<String, dynamic>);
}
