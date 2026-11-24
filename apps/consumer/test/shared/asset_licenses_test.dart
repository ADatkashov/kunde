import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'redistributed fonts and illustrations include their license in the bundle',
      () async {
    expect(
        await rootBundle
            .loadString('packages/kunde_design/assets/fonts/LICENSE.txt'),
        contains('SIL OPEN FONT LICENSE'));
    expect(await rootBundle.loadString('assets/illustrations/LICENSE.txt'),
        contains('MIT License'));
  });
}
