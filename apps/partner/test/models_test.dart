import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_partner/core/format.dart';
import 'package:kunde_partner/data/models.dart';

import 'support/fake_backend.dart';

void main() {
  test(
      'parses a real partner inbox entry (order nested, allowedNext at entry level)',
      () {
    final o = PartnerOrder.fromJson(orderEntry());
    expect(o.id, orderId);
    expect(o.status, 'PLACED');
    expect(o.isNew, isTrue);
    expect(o.isActive, isTrue);
    expect(o.restaurantName, 'Кухня партнёра');
    expect(o.items.map((l) => l.name), ['Лагман', 'Чай']);
    expect(o.itemCount, 3);
    expect(o.totalMinor, 410000);
    expect(o.allowedNext, ['ACCEPTED', 'CANCELLED']);
    expect(o.respondBy, isNotNull);
    expect(o.shortRef, hasLength(6));
    expect(o.shortRef, isNot(contains('-')));
  });

  test(
      'rejects an order entry without identity instead of showing half a record',
      () {
    expect(() => PartnerOrder.fromJson({'allowedNext': []}),
        throwsFormatException);
    expect(
        () => PartnerOrder.fromJson({
              'order': {'status': 'PLACED'}
            }),
        throwsFormatException);
    expect(() => PartnerBooking.fromJson({'status': 'PENDING'}),
        throwsFormatException);
  });

  test('parses a booking with server-provided actions', () {
    final b = PartnerBooking.fromJson(bookingJson());
    expect(b.isPending, isTrue);
    expect(b.allowedActions, ['CONFIRM', 'REJECT']);
    expect(b.serviceName, 'Стрижка');
    expect(b.masterName, 'Алия');
    expect(b.startsAt, isNotNull);
  });

  test('partner membership reads displayName and role', () {
    final p = PartnerMembership.fromJson({
      'id': partnerId,
      'displayName': 'Салон',
      'verificationStatus': 'APPROVED',
      'role': 'MANAGER',
    });
    expect(p.name, 'Салон');
    expect(p.approved, isTrue);
    expect(p.canManage, isTrue);
    expect(p.isOwner, isFalse);
    final op = PartnerMembership.fromJson({
      'id': 'x',
      'displayName': 'A',
      'verificationStatus': 'PENDING',
      'role': 'OPERATOR'
    });
    expect(op.approved, isFalse);
    expect(op.canManage, isFalse);
  });

  test('money, time and countdown formatting', () {
    expect(formatMoney(410000), '4 100 ₸');
    expect(formatMoney(150), '1,50 ₸');
    expect(formatMoney(0), '0 ₸');
    expect(
        minutesLeft(
            DateTime(2026, 1, 1, 12, 5), DateTime(2026, 1, 1, 12, 0, 30)),
        5);
    expect(
        minutesLeft(DateTime(2026, 1, 1, 12, 0), DateTime(2026, 1, 1, 12, 5)),
        0);
  });
}
