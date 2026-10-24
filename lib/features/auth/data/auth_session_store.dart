import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class AuthSessionStore {
  Future<String?> readToken();
  Future<void> saveToken(String token);
  Future<void> clear();
}

class SecureAuthSessionStore implements AuthSessionStore {
  const SecureAuthSessionStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  final FlutterSecureStorage _storage;
  static const _key = 'connectly_auth_session';

  @override
  Future<String?> readToken() => _storage.read(key: _key);

  @override
  Future<void> saveToken(String token) =>
      _storage.write(key: _key, value: token);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}
