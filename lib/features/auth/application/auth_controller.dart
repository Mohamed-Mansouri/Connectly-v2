import 'package:flutter/foundation.dart';

import '../data/auth_session_store.dart';
import '../data/biometric_access.dart';
import '../domain/auth_models.dart';

class AuthController extends ChangeNotifier {
  AuthController(
      {required AuthRepository repository,
      required AuthSessionStore store,
      BiometricAccess? biometrics,
      BiometricSettingsStore? biometricSettings,
      BiometricSessionRepository? biometricSessions})
      : _repository = repository,
        _store = store,
        _biometrics = biometrics,
        _biometricSettings = biometricSettings,
        _biometricSessions = biometricSessions;

  final AuthRepository _repository;
  final AuthSessionStore _store;
  final BiometricAccess? _biometrics;
  final BiometricSettingsStore? _biometricSettings;
  final BiometricSessionRepository? _biometricSessions;
  AuthUser? _user;
  String? _token;
  bool _restoring = true;
  String? _startupMessage;
  BiometricCredential? _biometricCredential;

  AuthUser? get user => _user;
  // Local session credential; never persist passwords or this token in Hive.
  String? get sessionToken => _token;
  bool get restoring => _restoring;
  String? get startupMessage => _startupMessage;
  bool get biometricsEnabled =>
      _user != null && _biometricCredential?.userId == _user!.id;
  bool get biometricLoginAvailable =>
      _biometricCredential != null &&
      _biometrics != null &&
      _biometricSessions != null;
  bool get canConfigureBiometrics =>
      _biometrics != null &&
      _biometricSettings != null &&
      _biometricSessions != null;

  Future<void> restore() async {
    _restoring = true;
    _startupMessage = null;
    _user = null;
    _token = null;
    _biometricCredential = null;
    notifyListeners();
    try {
      _biometricCredential = await _biometricSettings?.readCredential();
      final token = await _store.readToken();
      if (_biometricCredential != null) {
        // A configured device starts at Login so either method can be chosen.
        if (token != null) {
          await _store.clear();
          try {
            await _repository.signOut(token);
          } catch (_) {
            // The unused session still expires in the repository.
          }
        }
      } else if (token != null) {
        _user = await _repository.currentUser(token);
        _token = token;
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
    final sessionToken = _token;
    final biometrics = _biometrics;
    final settings = _biometricSettings;
    final sessions = _biometricSessions;
    if (user == null ||
        sessionToken == null ||
        biometrics == null ||
        settings == null ||
        sessions == null) {
      throw const AuthException('Sign in to enable fingerprint login.');
    }
    if (biometricsEnabled) return;
    try {
      if (!await biometrics.available()) {
        throw const AuthException(
            'Enroll a fingerprint on this device before enabling login.');
      }
      if (!await biometrics.authenticate()) return;
      if (_user?.id != user.id) return;
    } on AuthException {
      rethrow;
    } catch (_) {
      throw const AuthException('Fingerprint setup is unavailable right now.');
    }
    final newToken = await sessions.createBiometricToken(sessionToken);
    final credential = BiometricCredential(userId: user.id, token: newToken);
    try {
      await settings.saveCredential(credential);
    } catch (_) {
      await sessions.revokeBiometricToken(newToken);
      throw const AuthException(
          'Could not save fingerprint login on this device.');
    }
    final previous = _biometricCredential;
    _biometricCredential = credential;
    notifyListeners();
    if (previous != null) {
      try {
        await sessions.revokeBiometricToken(previous.token);
      } catch (_) {
        // The replaced credential still expires in the repository.
      }
    }
  }

  Future<void> disableBiometrics() async {
    final credential = _biometricCredential;
    await _biometricSettings?.clear();
    _biometricCredential = null;
    notifyListeners();
    if (credential != null) {
      await _biometricSessions?.revokeBiometricToken(credential.token);
    }
  }

  Future<void> signInWithBiometrics() async {
    final credential = _biometricCredential;
    final biometrics = _biometrics;
    final sessions = _biometricSessions;
    if (credential == null || biometrics == null || sessions == null) {
      throw const AuthException('Set up fingerprint login from Profile first.');
    }
    try {
      if (!await biometrics.available()) {
        throw const AuthException(
            'Fingerprint is unavailable. Use your password instead.');
      }
      if (!await biometrics.authenticate()) {
        throw const AuthException('Fingerprint was not recognized. Try again.');
      }
    } on AuthException {
      rethrow;
    } catch (_) {
      throw const AuthException(
          'Fingerprint login is unavailable. Use your password instead.');
    }
    try {
      final session = await sessions.signInWithBiometricToken(credential.token);
      if (session.user.id != credential.userId) {
        throw const AuthException('Fingerprint account changed.',
            statusCode: 401);
      }
      await _accept(session);
    } on AuthException catch (error) {
      if (error.statusCode == 401) {
        await disableBiometrics();
        throw const AuthException(
            'Fingerprint login expired. Sign in with your password and enable it again.');
      }
      rethrow;
    }
  }

  Future<void> signOut() async {
    final token = _token;
    // Clear saved credentials before releasing the current account.
    await _store.clear();
    _token = null;
    _user = null;
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
