import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'auth/partner_session.dart';
import 'data/partner_api.dart';
import 'data/partner_operations.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const KundePartnerApp());
}

/// Separate Partner application entry point. This foundation does not grant
/// access to partner data or bypass the server's membership authorization.
class KundePartnerApp extends StatelessWidget {
  const KundePartnerApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'KUNDE Partner',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF087F5B)),
          useMaterial3: true,
        ),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('ru'), Locale('kk'), Locale('en')],
        home: const PartnerLoginScreen(),
      );
}

class PartnerFoundationScreen extends StatelessWidget {
  const PartnerFoundationScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('KUNDE Partner')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.storefront_outlined, size: 56),
                SizedBox(height: 16),
                Text('KUNDE Partner',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                SizedBox(height: 12),
                Text(
                  'Отдельное приложение партнёра. '
                  'Авторизация и рабочие операции будут перенесены '
                  'из существующего кабинета после проверки контрактов.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
}

class PartnerLoginScreen extends StatefulWidget {
  const PartnerLoginScreen({super.key});
  @override
  State<PartnerLoginScreen> createState() => _PartnerLoginScreenState();
}

class _PartnerLoginScreenState extends State<PartnerLoginScreen> {
  final phone = TextEditingController();
  final code = TextEditingController();
  final partnerId = TextEditingController();
  final session = PartnerSession(
    apiBase: Uri.parse(const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://kunde-backend-ty81.onrender.com/api/v1/',
    )),
  );
  bool handedOff = false;
  bool requested = false;
  bool busy = false;
  String? error;

  Future<void> execute(Future<void> Function() action) async {
    setState(() { busy = true; error = null; });
    try { await action(); }
    catch (_) { if (mounted) setState(() => error = 'Не удалось выполнить запрос. Проверьте данные и соединение.'); }
    finally { if (mounted) setState(() => busy = false); }
  }

  @override
  void dispose() {
    phone.dispose(); code.dispose(); partnerId.dispose();
    if (!handedOff) session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('KUNDE Partner')),
    body: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(24), children: [
        const Icon(Icons.storefront_outlined, size: 64),
        const SizedBox(height: 20),
        const Text('Вход для партнёров', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        TextField(controller: phone, keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Телефон (+7...)')),
        if (requested) TextField(controller: code, keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Код подтверждения')),
        TextField(controller: partnerId,
          decoration: const InputDecoration(labelText: 'ID партнёра (DEV)')),
        if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: busy ? null : () => execute(() async {
            if (!requested) {
              await session.requestOtp(phone.text.trim());
              if (mounted) setState(() => requested = true);
              return;
            }
            if (partnerId.text.trim().isEmpty) {
              throw const FormatException('Partner ID required');
            }
            await session.verifyOtp(phone.text.trim(), code.text.trim());
            final api = PartnerApi(
              baseUri: session.apiBase, accessToken: session.accessToken);
            final ops = PartnerOperations(api, partnerId.text.trim());
            try {
              // Server verifies APPROVED membership and denies unauthorized users.
              await ops.activeOrders();
            } catch (_) {
              api.close();
              await session.logout();
              rethrow;
            }
            if (!mounted) { api.close(); return; }
            handedOff = true;
            Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
              builder: (_) => PartnerDashboard(
                session: session, api: api, operations: ops)));
          }),
          child: Text(busy ? 'Подождите...' : requested ? 'Войти' : 'Получить код'),
        ),
      ]),
    )),
  );
}

class PartnerDashboard extends StatefulWidget {
  const PartnerDashboard({
    required this.session, required this.api, required this.operations, super.key,
  });
  final PartnerSession session;
  final PartnerApi api;
  final PartnerOperations operations;
  @override
  State<PartnerDashboard> createState() => _PartnerDashboardState();
}

class _PartnerDashboardState extends State<PartnerDashboard> {
  int tab = 0;
  late Future<Map<String, dynamic>> data = load();
  Future<Map<String, dynamic>> load() {
    switch (tab) {
      case 0: return widget.operations.activeOrders();
      case 1: return widget.operations.bookingRequests();
      default: return widget.operations.restaurants();
    }
  }
  void refresh() => setState(() => data = load());
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('KUNDE Partner'), actions: [
      IconButton(onPressed: refresh, icon: const Icon(Icons.refresh), tooltip: 'Обновить'),
      IconButton(onPressed: () async {
        try { await widget.session.logout(); }
        catch (_) { /* local session is cleared even if server is unavailable */ }
        widget.api.close();
        widget.session.dispose();
        if (context.mounted) Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const PartnerLoginScreen()),
          (_) => false);
      }, icon: const Icon(Icons.logout), tooltip: 'Выйти'),
    ]),
    body: FutureBuilder<Map<String, dynamic>>(
      future: data,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Не удалось загрузить данные: ${snapshot.error is PartnerApiException ? (snapshot.error as PartnerApiException).statusCode : 'ошибка сети'}'));
        }
        final value = snapshot.data ?? {};
        return ListView(padding: const EdgeInsets.all(16), children: [
          Text(['Заказы', 'Записи', 'Рестораны'][tab],
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          // Read-only first iteration: do not assume a server response shape.
          Text(const JsonEncoder.withIndent('  ').convert(value)),
        ]);
      },
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: tab,
      onDestinationSelected: (index) => setState(() {
        tab = index; data = load();
      }),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.receipt_long), label: 'Заказы'),
        NavigationDestination(icon: Icon(Icons.event), label: 'Записи'),
        NavigationDestination(icon: Icon(Icons.restaurant), label: 'Каталог'),
      ],
    ),
  );
}
