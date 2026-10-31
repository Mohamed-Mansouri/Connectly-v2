import 'package:connectly/features/auth/application/auth_controller.dart';
import 'package:connectly/features/auth/data/auth_session_store.dart';
import 'package:connectly/features/auth/data/biometric_access.dart';
import 'package:connectly/features/auth/presentation/auth_gate.dart';
import 'package:connectly/features/auth/presentation/login_screen.dart';
import 'package:connectly/features/auth/domain/auth_models.dart';
import 'package:flutter/material.dart';
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

class FakeBiometricAccess implements BiometricAccess {
  bool isAvailable = true;
  bool verified = true;
  int prompts = 0;
  @override
  Future<bool> available() async => isAvailable;
  @override
  Future<bool> authenticate() async {
    prompts++;
    return verified;
  }
}

class MemoryBiometricSettings implements BiometricSettingsStore {
  BiometricCredential? credential;
  @override
  Future<BiometricCredential?> readCredential() async => credential;
  @override
  Future<void> saveCredential(BiometricCredential credential) async =>
      this.credential = credential;
  @override
  Future<void> clear() async => credential = null;
}

class FakeBiometricSessions implements BiometricSessionRepository {
  final revoked = <String>[];
  bool expired = false;
  @override
  Future<String> createBiometricToken(String sessionToken) async {
    expect(sessionToken, 'session-1');
    return 'biometric-token';
  }

  @override
  Future<AuthSession> signInWithBiometricToken(String biometricToken) async {
    if (expired || biometricToken != 'biometric-token') {
      throw const AuthException('Expired', statusCode: 401);
    }
    return AuthSession(token: 'fingerprint-session', user: testUser);
  }

  @override
  Future<void> revokeBiometricToken(String biometricToken) async {
    revoked.add(biometricToken);
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
  testWidgets('login offers fingerprint beside the password form',
      (tester) async {
    final store = MemorySessionStore()..token = 'saved-session';
    final settings = MemoryBiometricSettings()
      ..credential =
          const BiometricCredential(userId: 'user-1', token: 'biometric-token');
    final biometric = FakeBiometricAccess()..verified = false;
    final auth = AuthController(
        repository: FakeAuthRepository(),
        store: store,
        biometrics: biometric,
        biometricSettings: settings,
        biometricSessions: FakeBiometricSessions());
    await auth.restore();
    expect(store.token, isNull);
    await tester.pumpWidget(MaterialApp(home: AuthGate(controller: auth)));
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byKey(const Key('login_submit')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('login_biometric')));
    await tester.tap(find.byKey(const Key('login_biometric')));
    await tester.pumpAndSettle();
    expect(biometric.prompts, 1);
    expect(find.text('Fingerprint was not recognized. Try again.'),
        findsOneWidget);
    expect(auth.user, isNull);
    await tester.pumpWidget(const SizedBox());
    auth.dispose();
  });

  test('fingerprint login survives sign-out and creates a new normal session',
      () async {
    final store = MemorySessionStore();
    final settings = MemoryBiometricSettings();
    final biometric = FakeBiometricAccess();
    final sessions = FakeBiometricSessions();
    final first = AuthController(
        repository: FakeAuthRepository(),
        store: store,
        biometrics: biometric,
        biometricSettings: settings,
        biometricSessions: sessions);
    await first.signIn('member@example.com', 'password');
    await first.enableBiometrics();
    expect(settings.credential?.userId, testUser.id);
    expect(first.biometricsEnabled, isTrue);
    await first.signOut();
    expect(store.token, isNull);
    expect(settings.credential, isNotNull);
    first.dispose();

    final restored = AuthController(
        repository: FakeAuthRepository(),
        store: store,
        biometrics: biometric,
        biometricSettings: settings,
        biometricSessions: sessions);
    await restored.restore();
    expect(restored.user, isNull);
    expect(restored.biometricLoginAvailable, isTrue);
    biometric.verified = false;
    await expectLater(
        restored.signInWithBiometrics(), throwsA(isA<AuthException>()));
    expect(restored.user, isNull);
    biometric.verified = true;
    await restored.signInWithBiometrics();
    expect(restored.user?.id, testUser.id);
    expect(store.token, 'fingerprint-session');
    await restored.signOut();
    expect(store.token, isNull);
    expect(settings.credential, isNotNull);
    await restored.signIn('member@example.com', 'password');
    expect(restored.biometricsEnabled, isTrue);
    await restored.signOut();
    await restored.disableBiometrics();
    expect(settings.credential, isNull);
    expect(sessions.revoked, ['biometric-token']);
    restored.dispose();
  });

  test('expired fingerprint credential returns to password login', () async {
    final settings = MemoryBiometricSettings()
      ..credential =
          const BiometricCredential(userId: 'user-1', token: 'biometric-token');
    final sessions = FakeBiometricSessions()..expired = true;
    final auth = AuthController(
        repository: FakeAuthRepository(),
        store: MemorySessionStore(),
        biometrics: FakeBiometricAccess(),
        biometricSettings: settings,
        biometricSessions: sessions);
    await auth.restore();
    await expectLater(
        auth.signInWithBiometrics(), throwsA(isA<AuthException>()));
    expect(auth.biometricLoginAvailable, isFalse);
    expect(settings.credential, isNull);
    expect(auth.user, isNull);
    auth.dispose();
  });

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
