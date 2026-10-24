import 'package:flutter/material.dart';

import '../../../app/app_shell.dart';
import '../application/auth_controller.dart';
import '../data/login_preferences.dart';
import 'login_screen.dart';
import 'signup_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({required this.controller, this.preferences, super.key});

  final AuthController controller;
  final LoginPreferences? preferences;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          if (controller.restoring) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (controller.user != null) return const AppShell();
          return LoginScreen(
            preferences: preferences,
            initialMessage: controller.startupMessage,
            onSignIn: controller.signIn,
            onCreateAccount: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SignupScreen(onSignUp: controller.signUp),
              ),
            ),
            onContinueAsGuest: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AppShell()),
            ),
          );
        },
      );
}
