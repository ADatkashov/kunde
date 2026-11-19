import 'features/executor/executor_screen.dart';
import 'features/identity/ride_operations_app.dart';

void main() => runRideOperations(
      'KUNDE Executor',
      (auth) => ExecutorScreen(auth: auth),
    );
