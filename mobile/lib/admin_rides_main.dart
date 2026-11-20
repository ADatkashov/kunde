import 'features/identity/ride_operations_app.dart';
import 'features/rides_admin/ride_admin_screen.dart';

void main() => runRideOperations(
      'KUNDE Rides Admin',
      (auth) => RideAdminScreen(auth: auth),
      sameOriginWeb: true,
    );
