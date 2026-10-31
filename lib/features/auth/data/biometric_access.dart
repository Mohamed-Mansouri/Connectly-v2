import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

abstract class BiometricAccess {
  Future<bool> available();
  Future<bool> authenticate();
}

class DeviceBiometricAccess implements BiometricAccess {
  DeviceBiometricAccess({LocalAuthentication? localAuthentication})
      : _localAuthentication = localAuthentication ?? LocalAuthentication();

  final LocalAuthentication _localAuthentication;

  @override
  Future<bool> available() async =>
      (await _localAuthentication.getAvailableBiometrics()).isNotEmpty;

  @override
  Future<bool> authenticate() => _localAuthentication.authenticate(
        localizedReason: 'Unlock your saved Connectly session',
        biometricOnly: true,
      );
}

abstract class BiometricSettingsStore {
  Future<String?> readEnabledUserId();
  Future<void> setEnabledUserId(String? userId);
}

class SecureBiometricSettingsStore implements BiometricSettingsStore {
  const SecureBiometricSettingsStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  final FlutterSecureStorage _storage;
  static const _key = 'connectly_biometric_user_id';

  @override
  Future<String?> readEnabledUserId() => _storage.read(key: _key);

  @override
  Future<void> setEnabledUserId(String? userId) => userId == null
      ? _storage.delete(key: _key)
      : _storage.write(key: _key, value: userId);
}
