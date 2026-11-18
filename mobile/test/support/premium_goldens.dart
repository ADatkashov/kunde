import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Use the bundled product font and SDK-pinned icons on Linux and CI.
Future<void> loadPremiumFonts() async {
  final config = File('.dart_tool/package_config.json');
  final packages = jsonDecode(await config.readAsString())['packages'] as List;
  final flutter = config.absolute.uri.resolve(
      packages.singleWhere((p) => p['name'] == 'flutter')['rootUri'] as String);
  final loader = FontLoader('KundeSans');
  for (final weight in ['Regular', 'Medium', 'Bold', 'ExtraBold', 'Black']) {
    loader.addFont(File('assets/fonts/NotoSans-$weight.ttf')
        .readAsBytes()
        .then(ByteData.sublistView));
  }
  await loader.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(File.fromUri(flutter.replace(path: '${flutter.path}/').resolve(
            '../../bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'))
        .readAsBytes()
        .then(ByteData.sublistView));
  await icons.load();
}

Future<void> premiumGolden(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final context = tester.element(find.byType(WidgetsApp).first);
    await Future.wait([
      for (final name in [
        'food',
        'grocery',
        'rides',
        'delivery',
        'home',
        'beauty',
        'health',
        'auto',
        'leisure',
        'services',
        'robot',
        'burger',
        'pizza',
        'coffee'
      ])
        precacheImage(AssetImage('assets/illustrations/$name.png'), context),
      for (final name in ['food', 'groceries', 'home-services', 'beauty'])
        precacheImage(AssetImage('assets/photos/$name.jpg'), context),
      for (final name in [
        'food-banner',
        'nearby-restaurants',
        'nearby-groceries',
        'nearby-home',
      ])
        precacheImage(AssetImage('assets/photos/$name.webp'), context),
    ]);
  });
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  await expectLater(
      find.byType(WidgetsApp).first, matchesGoldenFile('goldens/$name.png'));
}
