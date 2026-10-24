import 'package:flutter/foundation.dart';

import '../data/auth_session_store.dart';
import '../domain/auth_models.dart';

class AuthController extends ChangeNotifier {
  AuthController(
      {required AuthRepository repository, required AuthSessionStore store})
      : _repository = repository,
        _store = store;

  final AuthRepository _repository;
  final AuthSessionStore _store;
  AuthUser? _user;
  String? _token;
  bool _restoring = true;
  String? _startupMessage;

  AuthUser? get user => _user;
  bool get restoring => _restoring;
  String? get startupMessage => _startupMessage;

  Future<void> restore() async {
    _restoring = true;
    _startupMessage = null;
    notifyListeners();
    try {
      final token = await _store.readToken();
      if (token != null) {
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
        _startupMessage = 'We couldn\'t reconnect. Please sign in again.';
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
        // The rejected local session still has a server-side expiry.
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

  Future<void> signOut() async {
    final token = _token;
    // Clear device credentials even when the network is unavailable.
    await _store.clear();
    _token = null;
    _user = null;
    notifyListeners();
    if (token != null) {
      try {
        await _repository.signOut(token);
      } catch (_) {
        // Offline revocation cannot reach the server; server expiry still applies.
      }
    }
  }
}
