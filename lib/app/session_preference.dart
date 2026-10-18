import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class SessionPreference {
  Future<bool> read();
  Future<void> write(bool staySignedIn);
}

/// Only the session policy is stored here. Credentials remain in Firebase Auth.
class SecureSessionPreference implements SessionPreference {
  static const _key = 'session.staySignedIn.v1';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  @override
  Future<bool> read() async {
    final value = await _storage.read(key: _key);
    if (value == null || value == 'true') return true;
    if (value == 'false') return false;
    throw StateError('SESSION_POLICY_INVALID');
  }

  @override
  Future<void> write(bool staySignedIn) =>
      _storage.write(key: _key, value: staySignedIn.toString());
}
