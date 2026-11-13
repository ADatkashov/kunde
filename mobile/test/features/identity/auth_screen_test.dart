import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kunde_mobile/main.dart';
import 'package:kunde_mobile/features/home/data/kunde_api.dart';
import 'package:kunde_mobile/features/identity/auth_repository.dart';

class MemoryVault implements TokenVault {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    this.value = value;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

class BrowserGateway implements OAuthGateway {
  bool registered = false;
  bool cancelled = false;
  bool logoutOffline = false;
  int logins = 0;
  Completer<void>? wait;
  @override
  Future<AuthTokens> login({bool register = false}) async {
    logins++;
    registered = register;
    await wait?.future;
    if (cancelled) throw IdentityUnavailable();
    return AuthTokens('access', 'refresh', 'id',
        DateTime.now().add(const Duration(minutes: 5)));
  }

  @override
  Future<AuthTokens> refresh(String token) => login();
  @override
  Future<void> logout(String? token) async {
    if (logoutOffline) throw IdentityUnavailable();
  }
}

void main() {
  setUpAll(() async {
    final configFile = File('.dart_tool/package_config.json');
    final config =
        jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
    final package = (config['packages'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((entry) => entry['name'] == 'flutter');
    final flutter =
        configFile.absolute.uri.resolve(package['rootUri'] as String);
    for (final entry in {
      'Roboto': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf'
    }.entries) {
      final uri = flutter
          .replace(path: '${flutter.path}/')
          .resolve('../../bin/cache/artifacts/material_fonts/${entry.value}');
      final loader = FontLoader(entry.key)
        ..addFont(File.fromUri(uri)
            .readAsBytes()
            .then((bytes) => ByteData.sublistView(bytes)));
      await loader.load();
    }
  });
  late BrowserGateway gateway;
  late MemoryVault vault;
  late AuthRepository auth;
  late KundeApi api;
  var status = 200;
  var offline = false;
  Map<String, dynamic> profile = {};
  void configure() {
    gateway = BrowserGateway();
    vault = MemoryVault();
    status = 200;
    offline = false;
    profile = {
      'id': 'synthetic',
      'displayName': 'Aruzhan',
      'preferredLanguage': 'en',
      'version': 0
    };
    auth = AuthRepository(
        gateway: gateway,
        vault: vault,
        apiBase: Uri.parse('https://api.example.test/api/v1/'),
        client: MockClient((request) async {
          if (offline) throw http.ClientException('offline');
          if (status != 200) return http.Response('{}', status);
          if (request.method == 'PATCH') {
            profile = {
              ...profile,
              ...jsonDecode(request.body) as Map<String, dynamic>,
              'version': 1
            };
          }
          return http.Response(jsonEncode(profile), 200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }));
    api = KundeApi(
        baseUri: auth.apiBase,
        client: MockClient((_) async => http.Response(
            jsonEncode({
              'releaseStage': 'FOUNDATION',
              'marketplaceEnabled': false,
              'oidcIssuerConfigured': true,
              'aiEnabled': false,
            }),
            200)));
  }

  tearDown(() {
    auth.dispose();
    api.close();
  });
  Future<void> start(WidgetTester tester) async {
    configure();
    await tester.pumpWidget(KundeApp(api: api, auth: auth));
    await tester.pumpAndSettle();
  }

  Future<void> login(WidgetTester tester) async {
    await start(tester);
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
  }

  Future<void> edit(WidgetTester tester) async {
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit profile'));
    await tester.pumpAndSettle();
  }

  testWidgets('signed-in shell has four tabs and keeps Profile working',
      (tester) async {
    await login(tester);
    final bar = find.byType(NavigationBar);
    expect(tester.widget<NavigationBar>(bar).destinations.length, 4);
    for (final label in ['Home', 'Search', 'Orders', 'Profile']) {
      expect(
          find.descendant(of: bar, matching: find.text(label)), findsOneWidget);
    }
    await tester.tap(find.descendant(of: bar, matching: find.text('Orders')));
    await tester.pumpAndSettle();
    expect(find.text('No orders yet'), findsOneWidget);
    await tester.tap(find.descendant(of: bar, matching: find.text('Profile')));
    await tester.pumpAndSettle();
    expect(find.text('Edit profile'), findsOneWidget);
  });

  testWidgets('splash restores stored session and loads profile before home',
      (tester) async {
    configure();
    vault.value = jsonEncode({
      'issuerVersion': 2,
      'context': auth.apiBase.toString(),
      'refresh': 'saved'
    });
    gateway.wait = Completer<void>();
    await tester.pumpWidget(KundeApp(api: api, auth: auth));
    await tester.pump();
    expect(find.text('Checking your session…'), findsOneWidget);
    gateway.wait!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsNothing);
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Aruzhan'), findsOneWidget);
  });
  testWidgets('login, edit, save, navigate home and logout', (tester) async {
    await login(tester);
    await edit(tester);
    await tester.enterText(find.byType(TextFormField), 'Dana');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(find.text('Profile saved'), findsOneWidget);
    expect(find.text('Dana'), findsOneWidget);
    expect(profile['version'], 1);
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsOneWidget);
    expect(vault.value, isNull);
  });
  testWidgets(
      'registration uses browser registration and prevents duplicate taps',
      (tester) async {
    await start(tester);
    gateway.wait = Completer<void>();
    await tester.tap(find.text('Create account'));
    await tester.pump();
    expect(find.text('Create account'), findsNothing);
    expect(gateway.logins, 1);
    expect(gateway.registered, true);
    gateway.wait!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
  });
  testWidgets('offline profile load can retry without another browser login',
      (tester) async {
    await start(tester);
    offline = true;
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Cannot connect. Check your connection and try again.'),
        findsOneWidget);
    offline = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(gateway.logins, 1);
  });
  testWidgets('conflict preserves draft and requires explicit reload',
      (tester) async {
    await login(tester);
    await edit(tester);
    await tester.enterText(find.byType(TextFormField), 'Draft');
    status = 409;
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(find.text('Draft'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Save changes'))
            .onPressed,
        isNull);
    status = 200;
    await tester.tap(find.text('Reload latest profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Aruzhan'), findsOneWidget);
  });
  testWidgets('401 removes protected routes and asks for reauthentication',
      (tester) async {
    await login(tester);
    await edit(tester);
    status = 401;
    await tester.enterText(find.byType(TextFormField), 'Draft');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(find.text('Your session expired. Sign in again.'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Aruzhan'), findsNothing);
  });
  testWidgets('locale switch works before sign in', (tester) async {
    await start(tester);
    await tester.tap(find.byIcon(Icons.language));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Қазақша'));
    await tester.pumpAndSettle();
    expect(find.text('Кіру'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.language));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Русский'));
    await tester.pumpAndSettle();
    expect(find.text('Войти'), findsOneWidget);
  });
  testWidgets(
      'invalid name remains in form and unsaved navigation asks to discard',
      (tester) async {
    await login(tester);
    await edit(tester);
    await tester.enterText(find.byType(TextFormField), ' ');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Enter a name of 1–80 characters without control characters.'),
        findsOneWidget);
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsOneWidget);
  });
  testWidgets('welcome renders on phone and preserves language controls',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await start(tester);
    await expectLater(
        find.byType(MaterialApp), matchesGoldenFile('goldens/welcome_en.png'));
    expect(tester.takeException(), isNull);
  });
  testWidgets('restricted account has a safe error and no profile navigation',
      (tester) async {
    await start(tester);
    status = 403;
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Account access is restricted. Contact support.'),
        findsOneWidget);
    expect(find.text('Edit profile'), findsNothing);
    gateway.logoutOffline = true;
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Signed out of the app. Your browser session may still be active.'),
        findsOneWidget);
    expect(vault.value, isNull);
  });
  testWidgets('failed first login does not claim an expired session',
      (tester) async {
    await start(tester);
    gateway.cancelled = true;
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Cannot connect. Check your connection and try again.'),
        findsOneWidget);
    expect(find.text('Your session expired. Sign in again.'), findsNothing);
    expect(auth.expired, false);
    expect(find.text('Sign in'), findsOneWidget);
  });
}
