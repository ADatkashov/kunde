import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'auth/partner_session.dart';
import 'data/partner_api.dart';
import 'data/partner_operations.dart';
import 'widgets/partner_records.dart';

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
          scaffoldBackgroundColor: const Color(0xFFF5F7F6),
          cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
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
  final session = PartnerSession(
    apiBase: Uri.parse(const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: '',
    )),
  );
  bool handedOff = false;
  bool requested = false;
  bool busy = false;
  String? error;

  Future<void> execute(Future<void> Function() action) async {
    setState(() { busy = true; error = null; });
    try { await action(); }
    catch (e) {
      if (mounted) {
        setState(() {
          if (e is PartnerAuthException) {
            error = e.code == 'INVALID_API_BASE'
                ? 'Адрес DEV API не настроен. Требуется новая APK.'
                : 'Ошибка авторизации: ${e.code}.';
          } else if (e is PartnerApiException) {
            error = e.statusCode == 403
                ? 'Нет доступа к кабинету партнёра для этого номера.'
                : 'Ошибка сервера партнёров (HTTP ${e.statusCode}).';
          } else if (e is FormatException) {
            error = 'Некорректные данные сервера: ${e.message}';
          } else {
            error = 'Не удалось подключиться к DEV серверу. Проверьте интернет.';
          }
        });
      }
    }
    finally { if (mounted) setState(() => busy = false); }
  }

  @override
  void dispose() {
    phone.dispose(); code.dispose();
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
        if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: busy ? null : () => execute(() async {
            if (session.apiBase.scheme != 'https' || session.apiBase.host.isEmpty) {
              throw const PartnerAuthException('INVALID_API_BASE');
            }
            if (!requested) {
              await session.requestOtp(phone.text.trim());
              if (mounted) setState(() => requested = true);
              return;
            }
            await session.verifyOtp(phone.text.trim(), code.text.trim());
            final api = PartnerApi(
              baseUri: session.apiBase, accessToken: session.accessToken);
            late final PartnerOperations ops;
            try {
              final memberships = await api.myPartners();
              final approved = memberships.where((p) =>
                  p['verificationStatus'] == 'APPROVED' &&
                  p['id'] is String && (p['id'] as String).isNotEmpty).toList();
              if (approved.isEmpty) {
                throw const FormatException('Нет одобренных партнёров для этого номера');
              }
              Map<String, dynamic>? selected;
              if (approved.length == 1) {
                selected = approved.first;
              } else {
                selected = await showDialog<Map<String, dynamic>>(
                  context: context,
                  builder: (dialogContext) => SimpleDialog(
                    title: const Text('Выберите партнёра'),
                    children: [
                      for (final partner in approved)
                        SimpleDialogOption(
                          onPressed: () => Navigator.pop(dialogContext, partner),
                          child: Text(partner['name']?.toString() ?? 'Партнёр'),
                        ),
                    ],
                  ),
                );
              }
              if (selected == null) { api.close(); return; }
              ops = PartnerOperations(api, selected['id'] as String);
            } catch (_) {
              api.close();
              await session.logout();
              rethrow;
            }
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
            if (!context.mounted) { api.close(); return; }
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

  Future<void> changeBooking(String bookingId, String action) async {
    final controller = TextEditingController();
    final reasonRequired = action == 'REJECT';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(action == 'CONFIRM' ? 'Подтвердить запись?' : 'Отклонить запись?'),
        content: reasonRequired
            ? TextField(controller: controller, maxLength: 300,
                decoration: const InputDecoration(labelText: 'Причина отклонения'))
            : const Text('Клиент получит обновлённый статус записи.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Назад')),
          FilledButton(onPressed: () {
            if (!reasonRequired || controller.text.trim().length >= 3) {
              Navigator.pop(dialogContext, true);
            }
          }, child: const Text('Подтвердить')),
        ],
      ),
    );
    final reason = controller.text.trim();
    controller.dispose();
    if (confirmed != true) return;
    try {
      await widget.operations.bookingAction(bookingId, action,
          reason: reasonRequired ? reason : null);
      if (mounted) refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Не удалось обновить запись. Повторите после обновления.'),
        ));
        refresh();
      }
    }
  }

  Future<void> changeOrder(String orderId, String status) async {
    String? reason;
    if (status == 'CANCELLED') {
      final controller = TextEditingController();
      reason = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Причина отмены'),
          content: TextField(
            controller: controller,
            maxLength: 300,
            decoration: const InputDecoration(
              labelText: 'Укажите причину (3–300 символов)',
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Назад')),
            FilledButton(onPressed: () {
              final value = controller.text.trim();
              if (value.length >= 3 && value.length <= 300) {
                Navigator.pop(dialogContext, value);
              }
            }, child: const Text('Подтвердить')),
          ],
        ),
      );
      controller.dispose();
      if (reason == null) return;
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Подтвердить действие?'),
          content: Text('Новый статус заказа: $status'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Назад')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Подтвердить')),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    try {
      await widget.operations.updateOrder(orderId, status, reason: reason);
      if (mounted) refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Не удалось обновить заказ. Обновите список и повторите.'),
        ));
        refresh();
      }
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('KUNDE Partner'), actions: [
      IconButton(onPressed: refresh, icon: const Icon(Icons.refresh), tooltip: 'Обновить'),
      IconButton(onPressed: () async {
        try { await widget.session.logout(); }
        catch (_) { /* local session is cleared even if server is unavailable */ }
        widget.api.close();
        widget.session.dispose();
        if (context.mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute<void>(builder: (_) => const PartnerLoginScreen()),
            (_) => false);
        }
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
        return Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Row(children: [
              Expanded(child: Text(['Заказы', 'Записи', 'Каталог'][tab],
                style: Theme.of(context).textTheme.headlineSmall)),
              const Icon(Icons.verified_user_outlined),
            ])),
          Expanded(child: PartnerRecords(payload: value,
            title: ['Заказ', 'Запись', 'Ресторан'][tab],
            onOrderAction: tab == 0 ? changeOrder : null,
            onBookingAction: tab == 1 ? changeBooking : null)),
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
