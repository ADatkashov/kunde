import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_partner/widgets/partner_records.dart';

void main() {
  testWidgets('renders status and record identifier as readable card',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(
      body: PartnerRecords(title: 'Заказ', payload: {
        'items': [
          {'id': 'order-42', 'status': 'PLACED', 'customerName': 'Клиент'}
        ]
      }),
    )));
    expect(find.text('Клиент'), findsOneWidget);
    expect(find.text('PLACED'), findsOneWidget);
    expect(find.text('№ order-42'), findsOneWidget);
  });

  testWidgets('empty list displays a friendly state', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(
      body: PartnerRecords(title: 'Заказ', payload: {'items': []}),
    )));
    expect(find.text('Нет записей'), findsOneWidget);
  });
}
