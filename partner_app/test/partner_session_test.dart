import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_partner/auth/partner_session.dart';

void main() {
  test('Partner OTP rejects insecure API base before sending requests', () async {
    final session = PartnerSession(
      apiBase: Uri.parse('http://example.test/api/v1/'),
    );
    await expectLater(
      session.requestOtp('+77000000002'),
      throwsA(isA<PartnerAuthException>()
          .having((e) => e.code, 'code', 'INVALID_API_BASE')),
    );
    session.dispose();
  });
}
