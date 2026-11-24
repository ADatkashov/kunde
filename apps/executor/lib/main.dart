import 'features/executor/executor_screen.dart';
import 'package:kunde_operator/ride_operations_app.dart';

void main() => runRideOperations(
      'KUNDE Executor',
      (auth) => ExecutorScreen(auth: auth, checkDeliveryMode: true),
    );
