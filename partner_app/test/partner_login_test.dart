import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_partner/main.dart';

void main() {
  testWidgets('standalone Partner starts at OTP login, not customer shell',
      (tester) async {
    await tester.pumpWidget(const KundePartnerApp());
    expect(find.text('Вход для партнёров'), findsOneWidget);
    expect(find.text('Получить код'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Заказы'), findsNothing);
  });
}
