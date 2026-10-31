import 'package:flutter/foundation.dart';

import '../data/auth_session_store.dart';
import '../data/biometric_access.dart';
import '../domain/auth_models.dart';

class AuthController extends ChangeNotifier {
  AuthController(
      {required AuthRepository repository,
      required AuthSessionStore store,
      BiometricAccess? biometrics,
      BiometricSettingsStore? biometricSettings})
      : _repository = repository,
        _store = store,
        _biometrics = biometrics,
        _biometricSettings = biometricSettings;

  final AuthRepository _repository;
  final AuthSessionStore _store;
  final BiometricAccess? _biometrics;
  final BiometricSettingsStore? _biometricSettings;
  AuthUser? _user;
  String? _token;
  bool _restoring = true;
  String? _startupMessage;
  bool _biometricsEnabled = false;
  bool _locked = false;

  AuthUser? get user => _user;
  // Local session credential; never persist passwords or this token in Hive.
  String? get sessionToken => _token;
  bool get restoring => _restoring;
  String? get startupMessage => _startupMessage;
  bool get biometricsEnabled => _biometricsEnabled;
  bool get locked => _locked;
  bool get canConfigureBiometrics =>
      _biometrics != null && _biometricSettings != null;

  Future<void> restore() async {
    _restoring = true;
    _startupMessage = null;
    _locked = false;
    _biometricsEnabled = false;
    notifyListeners();
    try {
      final token = await _store.readToken();
      if (token != null) {
        _user = await _repository.currentUser(token);
        _token = token;
        try {
          _biometricsEnabled =
              await _biometricSettings?.readEnabledUserId() == _user!.id;
          _locked = _biometricsEnabled;
        } catch (_) {
          // Require password if biometric settings cannot be read safely.
          _locked = true;
        }
      }
    } on AuthException catch (error) {
      _user = null;
      _token = null;
      if (error.statusCode == 401) {
        try {
          await _store.clear();
        } catch (_) {
          _startupMessage =
              'We couldn\'t restore your session. Please sign in again.';
        }
      } else {
        _startupMessage =
            'We couldn\'t open your account. Please sign in again.';
      }
    } catch (_) {
      _user = null;
      _token = null;
      _startupMessage =
          'We couldn\'t restore your session. Please sign in again.';
    } finally {
      _restoring = false;
      notifyListeners();
    }
  }

  Future<void> _accept(AuthSession session) async {
    try {
      await _store.saveToken(session.token);
    } catch (_) {
      try {
        await _repository.signOut(session.token);
      } catch (_) {
        // The rejected session still expires in the repository.
      }
      throw const AuthException(
        'We couldn\'t save your session on this device. Please try again.',
      );
    }
    _token = session.token;
    _user = session.user;
    _locked = false;
    _biometricsEnabled = false;
    _startupMessage = null;
    notifyListeners();
  }

  Future<void> signIn(String email, String password) async {
    await _accept(await _repository.signIn(email, password));
  }

  Future<void> signUp(String name, String email, String password) async {
    await _accept(await _repository.signUp(name, email, password));
  }

  Future<void> refreshUser() async {
    final token = _token;
    if (token == null) return;
    _user = await _repository.currentUser(token);
    notifyListeners();
  }

  Future<void> enableBiometrics() async {
    final user = _user;
    final biometrics = _biometrics;
    final settings = _biometricSettings;
    if (user == null || biometrics == null || settings == null) {
      throw const AuthException('Sign in to enable fingerprint unlock.');
    }
    try {
      if (!await biometrics.available()) {
        throw const AuthException(
            'Enroll a fingerprint on this device before enabling unlock.');
      }
      if (!await biometrics.authenticate()) return;
      await settings.setEnabledUserId(user.id);
    } on AuthException {
      rethrow;
    } catch (_) {
      throw const AuthException('Fingerprint setup is unavailable right now.');
    }
    if (_user?.id == user.id) {
      _biometricsEnabled = true;
      notifyListeners();
    }
  }

  Future<void> disableBiometrics() async {
    await _biometricSettings?.setEnabledUserId(null);
    _biometricsEnabled = false;
    _locked = false;
    notifyListeners();
  }

  void lock() {
    if (_user == null || !_biometricsEnabled) return;
    _locked = true;
    notifyListeners();
  }

  Future<bool> unlockWithBiometrics() async {
    final biometrics = _biometrics;
    if (!_locked || biometrics == null) return false;
    try {
      final verified = await biometrics.authenticate();
      if (verified && _user != null) {
        _locked = false;
        notifyListeners();
      }
      return verified;
    } catch (_) {
      throw const AuthException(
          'Fingerprint unlock is unavailable. Use your password instead.');
    }
  }

  Future<void> signOut() async {
    final token = _token;
    // Clear saved credentials before releasing the current account.
    await _store.clear();
    try {
      await _biometricSettings?.setEnabledUserId(null);
    } catch (_) {
      // The primary session still signs out even if this preference cannot be cleared.
    }
    _token = null;
    _user = null;
    _locked = false;
    _biometricsEnabled = false;
    notifyListeners();
    if (token != null) {
      try {
        await _repository.signOut(token);
      } catch (_) {
        // A storage failure must not prevent local sign-out; expiry still applies.
      }
    }
  }
}
