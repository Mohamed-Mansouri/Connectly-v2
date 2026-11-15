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
  List<BiometricCredential> _biometricCredentials = [];

  AuthUser? get user => _user;
  // Local session credential; never persist passwords or this token in Hive.
  String? get sessionToken => _token;
  bool get restoring => _restoring;
  String? get startupMessage => _startupMessage;
  bool get biometricsEnabled =>
      _user != null && _credentialFor(userId: _user!.id) != null;
  bool get biometricLoginAvailable =>
      _biometricCredentials.isNotEmpty &&
      _biometrics != null &&
      _biometricSessions != null;

  /// Whether the login screen should offer fingerprint for [email].
  bool canUseBiometricsFor(String email) =>
      biometricLoginAvailable && _credentialFor(email: email) != null;

  static String _normalize(String email) => email.trim().toLowerCase();
  BiometricCredential? _credentialFor({String? userId, String? email}) {
    final wanted = email == null ? null : _normalize(email);
    for (final credential in _biometricCredentials) {
      if (userId != null && credential.userId == userId) return credential;
      if (wanted != null &&
          wanted.isNotEmpty &&
          _normalize(credential.email) == wanted) {
        return credential;
      }
    }
    return null;
  }

  Future<void> _saveCredentials(List<BiometricCredential> credentials) async {
    await _biometricSettings?.saveCredentials(credentials);
    _biometricCredentials = credentials;
  }

  /// Fills in or refreshes each credential's email from its account and drops
  /// credentials whose token has expired.
  Future<void> _syncCredentialEmails() async {
    var changed = false;
    final kept = <BiometricCredential>[];
    for (final credential in _biometricCredentials) {
      try {
        final user = await _repository.currentUser(credential.token);
        if (user.id != credential.userId) {
          changed = true;
          continue;
        }
        if (user.email != credential.email) changed = true;
        kept.add(credential.withEmail(user.email));
      } on AuthException catch (error) {
        if (error.statusCode == 401) {
          changed = true;
        } else {
          kept.add(credential);
        }
      } catch (_) {
        kept.add(credential);
      }
    }
    if (changed) await _saveCredentials(kept);
  }

  bool get canConfigureBiometrics =>
      _biometrics != null &&
      _biometricSettings != null &&
      _biometricSessions != null;

  Future<void> restore() async {
    _restoring = true;
    _startupMessage = null;
    _user = null;
    _token = null;
    _biometricCredentials = [];
    notifyListeners();
    try {
      _biometricCredentials = await _biometricSettings?.readCredentials() ?? [];
      try {
        await _syncCredentialEmails();
      } catch (_) {
        // Credentials stay usable even if their emails could not be refreshed.
      }
      final token = await _store.readToken();
      if (_biometricCredentials.isNotEmpty) {
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
    final user = await _repository.currentUser(token);
    _user = user;
    // Keep fingerprint login following this account after an email change.
    final credential = _credentialFor(userId: user.id);
    if (credential != null && credential.email != user.email) {
      try {
        await _saveCredentials([
          for (final c in _biometricCredentials)
            c.userId == user.id ? c.withEmail(user.email) : c
        ]);
      } catch (_) {
        // The next app start refreshes the email again.
      }
    }
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
    final credential = BiometricCredential(
        userId: user.id, token: newToken, email: user.email);
    final previous = _credentialFor(userId: user.id);
    try {
      await _saveCredentials([
        ..._biometricCredentials.where((c) => c.userId != user.id),
        credential
      ]);
    } catch (_) {
      await sessions.revokeBiometricToken(newToken);
      throw const AuthException(
          'Could not save fingerprint login on this device.');
    }
    notifyListeners();
    if (previous != null) {
      try {
        await sessions.revokeBiometricToken(previous.token);
      } catch (_) {
        // The replaced credential still expires in the repository.
      }
    }
  }

  /// Turns off fingerprint login for the signed-in account only; other
  /// accounts on this phone keep theirs.
  Future<void> disableBiometrics() async {
    final user = _user;
    final credential = user == null ? null : _credentialFor(userId: user.id);
    if (credential != null) await _removeCredential(credential);
  }

  Future<void> _removeCredential(BiometricCredential credential) async {
    await _saveCredentials([
      for (final c in _biometricCredentials)
        if (c.userId != credential.userId) c
    ]);
    notifyListeners();
    try {
      await _biometricSessions?.revokeBiometricToken(credential.token);
    } catch (_) {
      // The removed local credential can no longer be accessed from this app.
    }
  }

  /// Signs in the account whose fingerprint login matches [email].
  Future<void> signInWithBiometrics(String email) async {
    final credential = _credentialFor(email: email);
    final biometrics = _biometrics;
    final sessions = _biometricSessions;
    if (credential == null || biometrics == null || sessions == null) {
      throw const AuthException(
          'Fingerprint login is not set up for this email. Enable it from Profile after signing in.');
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
        await _removeCredential(credential);
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
