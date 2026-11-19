import '../identity/auth_repository.dart';
import 'data/auto_api.dart';

/// Everything the Auto screens need, created once by the app and passed down explicitly.
class AutoServices {
  AutoServices({required this.api, required this.auth});

  final AutoApi api;
  final AuthRepository auth;
}
