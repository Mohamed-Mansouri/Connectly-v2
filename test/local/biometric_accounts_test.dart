import 'package:connectly/features/auth/application/auth_controller.dart';
import 'package:connectly/features/auth/data/local_passwords.dart';
import 'package:connectly/features/auth/data/sqlite_auth_repository.dart';
import 'package:connectly/shared/data/local_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../features/auth/auth_controller_test.dart'
    show FakeBiometricAccess, MemoryBiometricSettings, MemorySessionStore;

void main() {
  sqfliteFfiInit();

  test('each local account keeps its own fingerprint login, chosen by email',
      () async {
    final database = await LocalDatabase.open(
        factory: databaseFactoryFfi, databasePath: inMemoryDatabasePath);
    addTearDown(database.close);
    final repository = SqliteAuthRepository(database,
        passwords: LocalPasswords(iterations: 1000));
    final settings = MemoryBiometricSettings();
    final biometric = FakeBiometricAccess();
    AuthController controller() => AuthController(
        repository: repository,
        store: MemorySessionStore(),
        biometrics: biometric,
        biometricSettings: settings,
        biometricSessions: repository);

    final auth = controller();
    addTearDown(auth.dispose);
    await auth.signUp('Alpha', 'alpha@example.test', 'correct password');
    final alphaId = auth.user!.id;
    await auth.enableBiometrics();
    await auth.signOut();
    await auth.signUp('Beta', 'beta@example.test', 'correct password');
    await auth.enableBiometrics();
    await auth.signOut();
    // Enabling Beta must not replace Alpha.
    expect(settings.credentials.map((c) => c.email),
        ['alpha@example.test', 'beta@example.test']);

    expect(auth.canUseBiometricsFor('ALPHA@example.test '), isTrue);
    expect(auth.canUseBiometricsFor('beta@example.test'), isTrue);
    expect(auth.canUseBiometricsFor('gamma@example.test'), isFalse);
    await expectLater(auth.signInWithBiometrics('gamma@example.test'),
        throwsA(isA<Object>()));

    await auth.signInWithBiometrics('alpha@example.test');
    expect(auth.user!.name, 'Alpha');
    // A profile email change carries fingerprint login with it.
    await database.db.update('users', {'email': 'alpha.new@example.test'},
        where: 'id = ?', whereArgs: [alphaId]);
    await auth.refreshUser();
    expect(auth.canUseBiometricsFor('alpha.new@example.test'), isTrue);
    expect(auth.canUseBiometricsFor('alpha@example.test'), isFalse);
    // Turning it off for Alpha leaves Beta's.
    await auth.disableBiometrics();
    await auth.signOut();
    expect(settings.credentials.single.email, 'beta@example.test');

    // A fresh start picks up emails changed while the app was closed.
    final betaId = settings.credentials.single.userId;
    await database.db.update('users', {'email': 'beta.new@example.test'},
        where: 'id = ?', whereArgs: [betaId]);
    final restarted = controller();
    addTearDown(restarted.dispose);
    await restarted.restore();
    expect(restarted.canUseBiometricsFor('beta.new@example.test'), isTrue);
    await restarted.signInWithBiometrics('beta.new@example.test');
    expect(restarted.user!.id, betaId);
  });
}
