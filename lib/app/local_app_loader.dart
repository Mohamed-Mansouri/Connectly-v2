import 'dart:async';
import 'package:flutter/material.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/auth/data/auth_session_store.dart';
import '../features/auth/data/biometric_access.dart';
import '../features/auth/data/login_preferences.dart';
import '../features/auth/data/sqlite_auth_repository.dart';
import '../features/discovery/data/demo_people_seeder.dart';
import '../shared/data/local_database.dart';
import 'connectly_app.dart';
import 'connectly_theme.dart';

class LocalAppLoader extends StatefulWidget {
  const LocalAppLoader({super.key});
  @override
  State<LocalAppLoader> createState() => _LocalAppLoaderState();
}

class _LocalAppLoaderState extends State<LocalAppLoader> {
  late Future<_LocalAppData> _startup;
  @override
  void initState() {
    super.initState();
    _startup = _open();
  }

  Future<_LocalAppData> _open() async {
    final database = await LocalDatabase.open();
    await seedDemoPeople(database);
    LoginPreferences? preferences;
    try {
      preferences = await HiveLoginPreferences.open();
    } catch (_) {
      debugPrint('Remembered email is unavailable.');
    }
    final authRepository = SqliteAuthRepository(database);
    final auth = AuthController(
        repository: authRepository,
        biometricSessions: authRepository,
        store:
            const SecureAuthSessionStore(key: 'connectly_local_auth_session'),
        biometrics: DeviceBiometricAccess(),
        biometricSettings: const SecureBiometricSettingsStore());
    unawaited(auth.restore());
    return _LocalAppData(database, auth, preferences);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_LocalAppData>(
      future: _startup,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          final data = snapshot.data!;
          return ConnectlyApp(
              database: data.database,
              authController: data.auth,
              loginPreferences: data.preferences);
        }
        return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ConnectlyTheme.dark,
            home: Scaffold(
              body: SafeArea(
                  child: Center(
                      child: snapshot.hasError
                          ? Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('Could not open local storage',
                                        style: TextStyle(
                                            fontSize: 23,
                                            fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 12),
                                    const Text(
                                        'Check that this phone has available storage, then try again.',
                                        textAlign: TextAlign.center),
                                    const SizedBox(height: 20),
                                    FilledButton(
                                        onPressed: () =>
                                            setState(() => _startup = _open()),
                                        child: const Text('Try again')),
                                  ]))
                          : const CircularProgressIndicator())),
            ));
      });
}

class _LocalAppData {
  _LocalAppData(this.database, this.auth, this.preferences);
  final LocalDatabase database;
  final AuthController auth;
  final LoginPreferences? preferences;
}
