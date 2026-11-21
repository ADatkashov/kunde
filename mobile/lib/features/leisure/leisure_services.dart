import '../identity/auth_repository.dart';
import 'data/leisure_api.dart';

/// Everything the Leisure and Events screens need, created once by the app and passed down explicitly. Events reuse the Leisure screens:
/// [forProduct] returns the same services reading the other product's catalogue.
class LeisureServices {
  LeisureServices({required this.api, required this.auth});

  final LeisureApi api;
  final AuthRepository auth;

  LeisureProduct get product => api.product;
  bool get isEvents => product == LeisureProduct.events;

  LeisureServices forProduct(LeisureProduct other) => other == product
      ? this
      : LeisureServices(api: api.forProduct(other), auth: auth);
}
