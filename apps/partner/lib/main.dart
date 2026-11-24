import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/app_controller.dart';
import 'app/settings.dart';
import 'auth/partner_session.dart';

/// DEV API base compiled into the build (`--dart-define=API_BASE_URL=…`).
const String kApiBaseUrl = String.fromEnvironment('API_BASE_URL');

/// Per-request timeout. DEV runs on a free tier whose cold start takes about a
/// minute, so DEV release builds pass a longer value.
const int kApiTimeoutSeconds =
    int.fromEnvironment('API_TIMEOUT_SECONDS', defaultValue: 30);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = SettingsController();
  const timeout = Duration(seconds: kApiTimeoutSeconds);
  final controller = AppController(
    session: PartnerSession(apiBase: Uri.parse(kApiBaseUrl), timeout: timeout),
    timeout: timeout,
  );
  await settings.load();
  runApp(KundePartnerApp(controller: controller, settings: settings));
  await controller.bootstrap();
}
