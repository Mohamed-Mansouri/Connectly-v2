import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import '../domain/auth_models.dart';

class BiometricCredential {
  const BiometricCredential({required this.userId, required this.token});
  final String userId;
  final String token;
}

abstract class BiometricSessionRepository {
  Future<String> createBiometricToken(String sessionToken);
  Future<AuthSession> signInWithBiometricToken(String biometricToken);
  Future<void> revokeBiometricToken(String biometricToken);
}

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
        localizedReason: 'Sign in to Connectly with your fingerprint',
        biometricOnly: true,
      );
}

abstract class BiometricSettingsStore {
  Future<BiometricCredential?> readCredential();
  Future<void> saveCredential(BiometricCredential credential);
  Future<void> clear();
}

class SecureBiometricSettingsStore implements BiometricSettingsStore {
  const SecureBiometricSettingsStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  final FlutterSecureStorage _storage;
  static const _key = 'connectly_biometric_credential';
  static const _legacyKey = 'connectly_biometric_user_id';

  @override
  Future<BiometricCredential?> readCredential() async {
    final encoded = await _storage.read(key: _key);
    if (encoded == null) {
      await _storage.delete(key: _legacyKey);
      return null;
    }
    final data = jsonDecode(encoded) as Map<String, dynamic>;
    return BiometricCredential(
        userId: data['userId'] as String, token: data['token'] as String);
  }

  @override
  Future<void> saveCredential(BiometricCredential credential) => _storage.write(
      key: _key,
      value:
          jsonEncode({'userId': credential.userId, 'token': credential.token}));

  @override
  Future<void> clear() => _storage.delete(key: _key);
}
