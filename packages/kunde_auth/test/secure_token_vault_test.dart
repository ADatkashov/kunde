import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunde_auth/auth_repository.dart';

void main() {
  const legacy = 'kunde.consumer.session.v1';

  test('role vaults use separate key spaces', () async {
    FlutterSecureStorage.setMockInitialValues({});
    const executor = SecureTokenVault.role('executor');
    const admin = SecureTokenVault.role('admin');
    await executor.write('E');
    await admin.write('A');
    expect(await executor.read(), 'E');
    expect(await admin.read(), 'A');
    expect(await const SecureTokenVault().read(), isNull);
  });

  test('a session stored under the Consumer key is migrated once', () async {
    FlutterSecureStorage.setMockInitialValues({legacy: 'OLD'});
    const executor = SecureTokenVault.role('executor');
    expect(await executor.read(), 'OLD');
    const raw = FlutterSecureStorage();
    expect(await raw.read(key: 'kunde.executor.session.v1'), 'OLD');
    expect(await raw.read(key: legacy), isNull);
    expect(await executor.read(), 'OLD');
  });

  test('an existing role session wins over the legacy one', () async {
    FlutterSecureStorage.setMockInitialValues(
        {legacy: 'OLD', 'kunde.admin.session.v1': 'NEW'});
    const admin = SecureTokenVault.role('admin');
    expect(await admin.read(), 'NEW');
  });

  test('clear removes both the role key and the legacy key', () async {
    FlutterSecureStorage.setMockInitialValues(
        {legacy: 'OLD', 'kunde.admin.session.v1': 'NEW'});
    const admin = SecureTokenVault.role('admin');
    await admin.clear();
    const raw = FlutterSecureStorage();
    expect(await raw.read(key: legacy), isNull);
    expect(await admin.read(), isNull);
  });
}
