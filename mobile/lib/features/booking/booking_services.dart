import '../beauty/data/beauty_api.dart';
import '../identity/auth_repository.dart';
import 'data/booking_api.dart';

/// Everything the booking screens need, created once by the app and passed down explicitly.
class BookingServices {
  BookingServices({required this.api, required this.auth});

  final BookingApi api;
  final AuthRepository auth;

  /// Beauty & Care discovery on the same transport (salons, service cards, promotions, favorites).
  late final BeautyApi beauty = BeautyApi(api);
}
