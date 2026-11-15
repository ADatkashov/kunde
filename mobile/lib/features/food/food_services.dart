import 'data/cart_controller.dart';
import 'data/food_api.dart';
import '../identity/auth_repository.dart';

/// Everything the Food screens need, created once by the app and passed down explicitly.
class FoodServices {
  FoodServices({required this.api, required this.cart, required this.auth});

  final FoodApi api;
  final CartController cart;
  final AuthRepository auth;
}
