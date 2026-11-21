import 'data/cart_controller.dart';
import 'data/food_api.dart';
import '../groceries/data/groceries_api.dart';
import '../groceries/data/groceries_services.dart';
import '../identity/auth_repository.dart';

/// Everything the Food screens need, created once by the app and passed down explicitly.
class FoodServices {
  FoodServices(
      {required this.api,
      required this.cart,
      required this.auth,
      this.groceriesApi});

  final FoodApi api;
  final CartController cart;
  final AuthRepository auth;

  /// KUNDE Groceries client; when set, the Groceries category opens the Groceries screens.
  final GroceriesApi? groceriesApi;

  /// Groceries screens' services (created once, shares this cart).
  late final GroceriesServices? groceries = groceriesApi == null
      ? null
      : GroceriesServices(api: groceriesApi!, food: this);
}
