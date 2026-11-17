import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/app_controller.dart';
import 'app/settings.dart';
import 'auth/partner_session.dart';

/// DEV API base compiled into the build (`--dart-define=API_BASE_URL=…`).
const String kApiBaseUrl = String.fromEnvironment('API_BASE_URL');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = SettingsController();
  final controller = AppController(
    session: PartnerSession(apiBase: Uri.parse(kApiBaseUrl)),
  );
  await settings.load();
  runApp(KundePartnerApp(controller: controller, settings: settings));
  await controller.bootstrap();
}
