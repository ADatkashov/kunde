import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

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
        home: const PartnerFoundationScreen(),
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
