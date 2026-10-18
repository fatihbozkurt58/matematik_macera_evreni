import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:matematik/app/session_preference.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('Fresh installation stays signed in by default', () async {
    expect(await SecureSessionPreference().read(), isTrue);
  });
  test('Only boolean policy survives a new preference instance', () async {
    await SecureSessionPreference().write(false);
    expect(await SecureSessionPreference().read(), isFalse);
    expect(await const FlutterSecureStorage().readAll(), {
      'session.staySignedIn.v1': 'false',
    });
    await SecureSessionPreference().write(true);
    expect(await SecureSessionPreference().read(), isTrue);
  });
  test('Corrupt policy fails closed', () async {
    FlutterSecureStorage.setMockInitialValues({
      'session.staySignedIn.v1': 'broken',
    });
    await expectLater(SecureSessionPreference().read(), throwsStateError);
  });
}
