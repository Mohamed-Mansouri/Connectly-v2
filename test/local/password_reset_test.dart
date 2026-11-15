import 'package:connectly/features/auth/application/auth_controller.dart';
import 'package:connectly/features/auth/data/biometric_access.dart';
import 'package:connectly/features/auth/data/local_passwords.dart';
import 'package:connectly/features/auth/data/password_reset_mailer.dart';
import 'package:connectly/features/auth/data/sqlite_auth_repository.dart';
import 'package:connectly/features/auth/domain/auth_models.dart';
import 'package:connectly/features/auth/presentation/auth_gate.dart';
import 'package:connectly/shared/data/local_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../features/auth/auth_controller_test.dart'
    show FakeBiometricAccess, MemoryBiometricSettings, MemorySessionStore;

class FakeMailer implements PasswordResetMailer {
  final sent = <({String to, String code})>[];
  bool fail = false;
  @override
  bool get configured => true;
  @override
  Future<void> sendCode({required String to, required String code}) async {
    if (fail) throw const AuthException('The email could not be sent.');
    sent.add((to: to, code: code));
  }
}

void main() {
  sqfliteFfiInit();
  late LocalDatabase database;
  late SqliteAuthRepository repository;
  late FakeMailer mailer;
  late MemoryBiometricSettings settings;
  AuthController controller() => AuthController(
      repository: repository,
      store: MemorySessionStore(),
      biometrics: FakeBiometricAccess(),
      biometricSettings: settings,
      biometricSessions: repository,
      passwordResets: repository,
      resetMailer: mailer);

  setUp(() async {
    database = await LocalDatabase.open(
        factory: databaseFactoryFfi, databasePath: inMemoryDatabasePath);
    repository = SqliteAuthRepository(database,
        passwords: LocalPasswords(iterations: 1000));
    mailer = FakeMailer();
    settings = MemoryBiometricSettings();
  });
  tearDown(() => database.close());

  test('a mailed code resets the password and signs out every session',
      () async {
    final auth = controller();
    addTearDown(auth.dispose);
    await auth.signUp('Amal', 'Amal@Example.com', 'old password');
    await auth.enableBiometrics();
    await auth.signOut();

    await expectLater(auth.requestPasswordReset('nobody@example.com'),
        throwsA(isA<AuthException>()));
    await auth.requestPasswordReset(' amal@example.com ');
    expect(mailer.sent.single.to, 'amal@example.com');
    final code = mailer.sent.single.code;
    expect(code, matches(RegExp(r'^\d{6}$')));
    // Only a hash is stored.
    final row = (await database.db.query('password_resets')).single;
    expect(row.values, isNot(contains(code)));
    // A second request inside the cooldown is refused.
    await expectLater(auth.requestPasswordReset('amal@example.com'),
        throwsA(isA<AuthException>()));

    final wrong = code == '111111' ? '222222' : '111111';
    await expectLater(
        auth.resetPassword('amal@example.com', wrong, 'new pass 1'),
        throwsA(isA<AuthException>()));
    await expectLater(auth.resetPassword('amal@example.com', code, 'short'),
        throwsA(isA<AuthException>()));
    await auth.resetPassword('amal@example.com', code, 'new password');

    await expectLater(repository.signIn('amal@example.com', 'old password'),
        throwsA(isA<AuthException>()));
    expect(
        (await repository.signIn('amal@example.com', 'new password')).user.name,
        'Amal');
    // Fingerprint login was revoked with the other sessions.
    expect(settings.credentials, isEmpty);
    expect(auth.canUseBiometricsFor('amal@example.com'), isFalse);
    // The code cannot be reused.
    await expectLater(
        auth.resetPassword('amal@example.com', code, 'another one'),
        throwsA(isA<AuthException>()));
  });

  test('codes lock after five wrong tries and expire', () async {
    final auth = controller();
    addTearDown(auth.dispose);
    await auth.signUp('Sami', 'sami@example.com', 'old password');
    await auth.signOut();
    await auth.requestPasswordReset('sami@example.com');
    final code = mailer.sent.single.code;
    final wrong = code == '111111' ? '222222' : '111111';
    for (var i = 0; i < 5; i++) {
      await expectLater(
          auth.resetPassword('sami@example.com', wrong, 'new password'),
          throwsA(isA<AuthException>()));
    }
    await expectLater(
        auth.resetPassword('sami@example.com', code, 'new password'),
        throwsA(isA<AuthException>()));

    // A failed email removes the code so the person can retry right away.
    mailer.fail = true;
    await expectLater(auth.requestPasswordReset('sami@example.com'),
        throwsA(isA<AuthException>()));
    expect(await database.db.query('password_resets'), isEmpty);
    mailer.fail = false;
    await auth.requestPasswordReset('sami@example.com');
    await database.db.update('password_resets', {
      'expires_at':
          localTimestamp(DateTime.now().subtract(const Duration(minutes: 1)))
    });
    await expectLater(
        auth.resetPassword(
            'sami@example.com', mailer.sent.last.code, 'new password'),
        throwsA(isA<AuthException>()));
  });

  testWidgets('forgot password flow from the login screen', (tester) async {
    final auth = controller();
    addTearDown(auth.dispose);
    await tester.runAsync(() async {
      await auth.signUp('Ines', 'ines@example.com', 'old password');
      await auth.signOut();
      await auth.restore();
    });
    await tester.pumpWidget(MaterialApp(home: AuthGate(controller: auth)));
    await tester.ensureVisible(find.byKey(const Key('login_forgot_password')));
    await tester.tap(find.byKey(const Key('login_forgot_password')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('reset_email')), 'ines@example.com');
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('reset_send')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    expect(find.textContaining('We sent a 6-digit code'), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('reset_code')), mailer.sent.single.code);
    await tester.enterText(
        find.byKey(const Key('reset_password')), 'new password');
    await tester.enterText(find.byKey(const Key('reset_confirm')), 'different');
    await tester.ensureVisible(find.byKey(const Key('reset_submit')));
    await tester.tap(find.byKey(const Key('reset_submit')));
    await tester.pump();
    expect(find.text('Passwords do not match.'), findsOneWidget);
    expect(find.textContaining('Resend code in'), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('reset_confirm')), 'new password');
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('reset_submit')));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();
    expect(find.text('Password updated. Sign in with your new password.'),
        findsOneWidget);
    await tester.runAsync(() async {
      expect(
          (await repository.signIn('ines@example.com', 'new password'))
              .user
              .name,
          'Ines');
    });
    await tester.pumpWidget(const SizedBox());
  });

  test('unconfigured Gmail sender refuses without sending', () async {
    const mailer = GmailPasswordResetMailer(user: '', password: '');
    expect(mailer.configured, isFalse);
    await expectLater(mailer.sendCode(to: 'a@b.c', code: '123456'),
        throwsA(isA<AuthException>()));
  });

  test('credential type still exported', () {
    expect(const BiometricCredential(userId: 'u', token: 't').email, '');
  });
}
