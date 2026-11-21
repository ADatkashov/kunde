import '../identity/auth_repository.dart';
import 'data/leisure_api.dart';

/// Everything the Leisure screens need, created once by the app and passed down explicitly.
class LeisureServices {
  LeisureServices({required this.api, required this.auth});

  final LeisureApi api;
  final AuthRepository auth;
}
