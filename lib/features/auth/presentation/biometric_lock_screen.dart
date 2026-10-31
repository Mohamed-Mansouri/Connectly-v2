import 'package:flutter/material.dart';
import '../application/auth_controller.dart';
import '../domain/auth_models.dart';

class BiometricLockScreen extends StatefulWidget {
  const BiometricLockScreen({required this.controller, super.key});

  final AuthController controller;

  @override
  State<BiometricLockScreen> createState() => _BiometricLockScreenState();
}

class _BiometricLockScreenState extends State<BiometricLockScreen> {
  bool _busy = false;
  String? _message;

  Future<void> _unlock() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (!await widget.controller.unlockWithBiometrics() && mounted) {
        setState(() => _message = 'Fingerprint was not recognized. Try again.');
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _usePassword() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.controller.signOut();
    } on AuthException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Connectly is locked')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.fingerprint, size: 76),
                  const SizedBox(height: 20),
                  Text('Welcome back, ${widget.controller.user?.name ?? ''}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 12),
                  const Text('Use your fingerprint to unlock this saved session.',
                      textAlign: TextAlign.center),
                  if (_message != null) ...[
                    const SizedBox(height: 16),
                    Text(_message!, textAlign: TextAlign.center),
                  ],
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    key: const Key('biometric_unlock'),
                    onPressed: _busy ? null : _unlock,
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('Unlock with fingerprint'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _usePassword,
                    child: const Text('Use password instead'),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
}
