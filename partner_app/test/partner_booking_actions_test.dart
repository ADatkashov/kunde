import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_partner/widgets/partner_records.dart';

void main() {
  testWidgets('requested booking exposes confirm and reject actions',
      (tester) async {
    final actions = <String>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: PartnerRecords(
        title: 'Запись',
        payload: {'bookings': [
          {'id': 'booking-1', 'status': 'REQUESTED'}
        ]},
        onBookingAction: (id, action) async => actions.add('$id:$action'),
      ),
    )));
    await tester.tap(find.text('Подтвердить'));
    await tester.pump();
    expect(actions, ['booking-1:CONFIRM']);
  });

  testWidgets('confirmed booking has no request actions', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: PartnerRecords(
        title: 'Запись',
        payload: {'bookings': [
          {'id': 'booking-1', 'status': 'CONFIRMED'}
        ]},
        onBookingAction: (_, __) async {},
      ),
    )));
    expect(find.text('Подтвердить'), findsNothing);
    expect(find.text('Отклонить'), findsNothing);
  });
}
