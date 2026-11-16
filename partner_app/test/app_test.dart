import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_partner/main.dart';

void main() {
  testWidgets('standalone Partner app has its own entry point', (tester) async {
    await tester.pumpWidget(const KundePartnerApp());
    expect(find.text('KUNDE Partner'), findsWidgets);
    expect(find.byIcon(Icons.storefront_outlined), findsOneWidget);
  });
}
