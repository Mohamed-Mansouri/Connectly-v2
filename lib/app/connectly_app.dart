import 'package:flutter/material.dart';

import '../features/auth/data/login_preferences.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/auth/presentation/auth_gate.dart';
import '../features/auth/presentation/auth_scope.dart';
import '../features/auth/presentation/login_screen.dart';
import 'connectly_theme.dart';
import 'app_shell.dart';
import '../shared/data/local_database.dart';
import 'local_data_scope.dart';

class ConnectlyApp extends StatelessWidget {
  const ConnectlyApp(
      {this.loginPreferences, this.authController, this.database, super.key});

  final LoginPreferences? loginPreferences;
  final AuthController? authController;
  final LocalDatabase? database;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Connectly',
      debugShowCheckedModeBanner: false,
      theme: ConnectlyTheme.dark,
      builder: (context, child) {
        Widget app = authController == null
            ? child!
            : AuthScope(controller: authController!, child: child!);
        if (database != null) {
          app = LocalDataScope(database: database!, child: app);
        }
        return app;
      },
      home: authController != null
          ? AuthGate(controller: authController!, preferences: loginPreferences)
          : Builder(
              builder: (context) => LoginScreen(
                preferences: loginPreferences,
                onContinueAsGuest: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AppShell()),
                ),
              ),
            ),
    );
  }
}
