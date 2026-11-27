import 'package:kunde_auth/auth_repository.dart';

import '../../home/data/kunde_api.dart';
import 'flowers_cart.dart';
import 'flowers_orders_api.dart';

/// Everything the Flowers & Gifts screens share: the public catalogue API, the signed-in order API (absent for guests)
/// and the cart that lives as long as the flowers section is open.
class FlowersServices {
  FlowersServices({required this.api, AuthRepository? auth})
      : orders = auth == null ? null : FlowersOrdersApi(auth);

  final KundeApi api;
  final FlowersOrdersApi? orders;
  final FlowersCart cart = FlowersCart();
}
