import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../food/data/cart_controller.dart';
import 'package:kunde_models/food_models.dart';
import '../../food/food_services.dart';
import 'groceries_api.dart';

/// Everything the Groceries screens need: the Groceries API, the shared Food services (cart, orders) and the
/// customer's favorite product ids.
class GroceriesServices {
  GroceriesServices({required this.api, required this.food}) {
    cartSync = GroceriesCartSync(api: api, food: food);
  }

  final GroceriesApi api;
  final FoodServices food;
  late final GroceriesCartSync cartSync;

  CartController get cart => food.cart;

  /// Ids of the customer's favorite products; empty until [loadFavorites] succeeds.
  final ValueNotifier<Set<String>> favorites = ValueNotifier(<String>{});

  List<Restaurant>? _stores;

  Future<List<Restaurant>> stores() async =>
      _stores ??= await food.api.restaurants(vertical: 'GROCERY');

  Future<Restaurant> storeFor(String id) async {
    var list = await stores();
    var found = list.where((s) => s.id == id).firstOrNull;
    if (found == null) {
      _stores = null;
      list = await stores();
      found = list.where((s) => s.id == id).firstOrNull;
    }
    if (found == null) {
      throw const GroceriesException(GroceriesFailure.notFound);
    }
    return found;
  }

  Future<void> loadFavorites() async {
    try {
      favorites.value = await api.favoriteIds();
    } on GroceriesException {
      // Favorites are a convenience: the catalog keeps working without them.
    }
  }

  /// Optimistic toggle; the previous state is restored and the error rethrown when the server refuses.
  Future<void> toggleFavorite(String productId) async {
    final was = favorites.value.contains(productId);
    final next = {...favorites.value};
    was ? next.remove(productId) : next.add(productId);
    favorites.value = next;
    try {
      await api.setFavorite(productId, !was);
    } on GroceriesException {
      final back = {...favorites.value};
      was ? back.add(productId) : back.remove(productId);
      favorites.value = back;
      rethrow;
    }
  }
}

/// Keeps the in-app cart and the server cart in step so that a grocery cart survives sign-out, a new device and an
/// app restart. Prices are never sent: the server recomputes them. A failed push (offline) keeps the local cart
/// working and is retried with the next change.
class GroceriesCartSync {
  GroceriesCartSync({required this.api, required this.food});

  final GroceriesApi api;
  final FoodServices food;
  Timer? _timer;
  bool _restoring = false;
  bool _attached = false;
  String? _serverStoreId;

  /// True while the server holds a grocery cart this client knows of and the last push failed.
  final ValueNotifier<bool> pending = ValueNotifier(false);

  void attach() {
    if (_attached) return;
    _attached = true;
    food.cart.addListener(_onCartChanged);
  }

  void dispose() {
    _timer?.cancel();
    if (_attached) food.cart.removeListener(_onCartChanged);
  }

  void _onCartChanged() {
    if (_restoring) return;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 600), push);
  }

  /// Loads the server cart into an empty local cart. Returns true when something was restored.
  Future<bool> restore(Future<Restaurant> Function(String id) storeFor) async {
    if (!food.cart.isEmpty) return false;
    final server = await api.cart();
    if (server.isEmpty) return false;
    final store = await storeFor(server.restaurantId!);
    _restoring = true;
    try {
      for (final line in server.lines) {
        if (line.issue == 'UNAVAILABLE' || line.issue == 'OUT_OF_STOCK') {
          continue;
        }
        food.cart.add(
          store,
          CartLine(
            dishId: line.dishId,
            name: line.name,
            emoji: line.emoji,
            tone: 'green',
            optionIds: line.optionIds,
            optionsText: '',
            unitPriceMinor: line.unitPriceMinor,
            quantity: line.quantity
                .clamp(1, line.maxQuantity < 1 ? 1 : line.maxQuantity),
            unit: line.unit,
            maxQuantity: line.maxQuantity,
            substitution: line.substitution,
            substituteDishIds: line.substituteDishIds,
          ),
        );
      }
    } finally {
      _restoring = false;
    }
    _serverStoreId = server.restaurantId;
    return !food.cart.isEmpty;
  }

  /// Replaces the in-app cart with the server cart (after the server cart was changed, for example by a list).
  Future<void> reloadFromServer(
      Future<Restaurant> Function(String id) storeFor) async {
    _restoring = true;
    try {
      food.cart.clear();
    } finally {
      _restoring = false;
    }
    await restore(storeFor);
  }

  Future<void> push() async {
    final cart = food.cart;
    try {
      final store = cart.restaurant;
      if (cart.isEmpty) {
        final previous = _serverStoreId;
        if (previous != null) {
          await api.saveCart(previous, const []);
          _serverStoreId = null;
        }
      } else if (store != null && store.vertical == 'GROCERY') {
        await api.saveCart(store.id,
            cart.lines.map((l) => l.toRequest()).toList(growable: false));
        _serverStoreId = store.id;
      }
      pending.value = false;
    } on GroceriesException {
      pending.value = true;
    }
  }
}
