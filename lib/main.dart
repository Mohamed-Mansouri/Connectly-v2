import 'dart:async';

import 'package:flutter/material.dart';

import 'app/connectly_app.dart';
import 'features/auth/data/login_preferences.dart';
import 'features/auth/data/auth_api.dart';
import 'features/auth/data/auth_session_store.dart';
import 'features/auth/application/auth_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LoginPreferences? preferences;
  try {
    preferences = await HiveLoginPreferences.open();
  } catch (_) {
    debugPrint('Login email preferences are unavailable.');
  }
  final auth = AuthController(
    repository: AuthApi(),
    store: const SecureAuthSessionStore(),
  );
  runApp(ConnectlyApp(loginPreferences: preferences, authController: auth));
  unawaited(auth.restore());
}
