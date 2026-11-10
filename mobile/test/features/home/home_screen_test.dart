import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_mobile/core/localization/kunde_localizations.dart';
import 'package:kunde_mobile/features/home/data/kunde_api.dart';
import 'package:kunde_mobile/features/home/presentation/home_screen.dart';
import 'package:kunde_mobile/shared/theme/kunde_theme.dart';

void main() {
  testWidgets('shows explicit unavailable state instead of demo services',
      (tester) async {
    final client = MockClient((_) async => http.Response(
        jsonEncode({
          'releaseStage': 'FOUNDATION',
          'marketplaceEnabled': false,
          'oidcIssuerConfigured': false,
          'aiEnabled': false,
        }),
        200));
    final api = KundeApi(
        baseUri: Uri.parse('https://api.example.test/api/v1/'), client: client);

    await tester.pumpWidget(MaterialApp(
      theme: KundeTheme.light,
      localizationsDelegates: KundeLocalizations.localizationsDelegates,
      supportedLocales: KundeLocalizations.supportedLocales,
      locale: const Locale('ru'),
      home: HomeScreen(api: api),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Сервисы пока не запущены'), findsOneWidget);
    expect(find.text('Сервер доступен'), findsOneWidget);
    expect(find.text('KUNDE AI пока недоступен'), findsOneWidget);
    expect(find.text('Еда и покупки'), findsNothing);
    api.close();
  });
}
