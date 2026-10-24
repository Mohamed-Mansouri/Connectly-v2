import 'package:connectly/features/auth/application/auth_controller.dart';
import 'package:connectly/features/auth/data/auth_session_store.dart';
import 'package:connectly/features/auth/domain/auth_models.dart';
import 'package:flutter_test/flutter_test.dart';

final testUser = AuthUser(
  id: 'user-1',
  name: 'Test Member',
  email: 'member@example.com',
  createdAt: DateTime.utc(2026, 10, 24),
);

class MemorySessionStore implements AuthSessionStore {
  String? token;
  bool failWrite = false;
  @override
  Future<String?> readToken() async => token;
  @override
  Future<void> saveToken(String token) async {
    if (failWrite) throw StateError('Storage unavailable');
    this.token = token;
  }

  @override
  Future<void> clear() async {
    token = null;
  }
}

class FakeAuthRepository implements AuthRepository {
  AuthException? restoreError;
  bool offlineLogout = false;
  final revoked = <String>[];
  @override
  Future<AuthSession> signIn(String email, String password) async =>
      AuthSession(token: 'session-1', user: testUser);
  @override
  Future<AuthSession> signUp(String name, String email, String password) =>
      signIn(email, password);
  @override
  Future<AuthUser> currentUser(String token) async {
    if (restoreError != null) throw restoreError!;
    return testUser;
  }

  @override
  Future<void> signOut(String token) async {
    revoked.add(token);
    if (offlineLogout) throw const AuthException('Offline');
  }
}

void main() {
  test('sign-in stores the session before exposing an authenticated user',
      () async {
    final store = MemorySessionStore();
    final auth = AuthController(repository: FakeAuthRepository(), store: store);
    await auth.restore();
    expect(auth.user, isNull);
    await auth.signIn('member@example.com', 'password');
    expect(store.token, 'session-1');
    expect(auth.user?.id, testUser.id);
    auth.dispose();
  });

  test('saved session is validated against the server on startup', () async {
    final store = MemorySessionStore()..token = 'saved-session';
    final auth = AuthController(repository: FakeAuthRepository(), store: store);
    await auth.restore();
    expect(auth.user?.email, testUser.email);
    expect(auth.restoring, isFalse);
    auth.dispose();
  });

  test('expired session is cleared without authenticating', () async {
    final store = MemorySessionStore()..token = 'expired';
    final repository = FakeAuthRepository()
      ..restoreError = const AuthException('Expired', statusCode: 401);
    final auth = AuthController(repository: repository, store: store);
    await auth.restore();
    expect(auth.user, isNull);
    expect(store.token, isNull);
    auth.dispose();
  });

  test('network failure preserves the token but does not authenticate',
      () async {
    final store = MemorySessionStore()..token = 'saved-session';
    final repository = FakeAuthRepository()
      ..restoreError = const AuthException('Offline');
    final auth = AuthController(repository: repository, store: store);
    await auth.restore();
    expect(auth.user, isNull);
    expect(store.token, 'saved-session');
    expect(auth.startupMessage, isNotNull);
    auth.dispose();
  });

  test('failed secure storage does not grant access and revokes new token',
      () async {
    final store = MemorySessionStore()..failWrite = true;
    final repository = FakeAuthRepository();
    final auth = AuthController(repository: repository, store: store);
    await expectLater(auth.signIn('member@example.com', 'password'),
        throwsA(isA<AuthException>()));
    expect(auth.user, isNull);
    expect(repository.revoked, ['session-1']);
    auth.dispose();
  });

  test('logout clears device credentials even if server is unreachable',
      () async {
    final store = MemorySessionStore();
    final repository = FakeAuthRepository()..offlineLogout = true;
    final auth = AuthController(repository: repository, store: store);
    await auth.signIn('member@example.com', 'password');
    await auth.signOut();
    expect(auth.user, isNull);
    expect(store.token, isNull);
    expect(repository.revoked, ['session-1']);
    auth.dispose();
  });
}
