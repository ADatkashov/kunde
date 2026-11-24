import 'package:kunde_operator/ride_operations_app.dart';
import 'features/rides_admin/ride_admin_screen.dart';

void main() => runRideOperations(
      'KUNDE Rides Admin',
      'admin',
      (auth) => RideAdminScreen(auth: auth),
      sameOriginWeb: true,
    );
