import 'package:flutter/material.dart';

import '../../../app/connectly_theme.dart';
import 'auth_scope.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _busy = false;

  Future<void> _signOut() async {
    final auth = AuthScope.maybeOf(context);
    if (auth == null || _busy) return;
    setState(() => _busy = true);
    try {
      await auth.signOut();
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('We couldn\'t sign you out. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthScope.maybeOf(context)?.user;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircleAvatar(
                    radius: 42,
                    backgroundColor: ConnectlyTheme.surface,
                    child: Icon(Icons.person_outline,
                        size: 44, color: ConnectlyTheme.yellow),
                  ),
                  const SizedBox(height: 24),
                  Text(user?.name ?? 'You\'re exploring as a guest',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontFamily: 'Urbanist',
                          fontSize: 28,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  Text(user?.email ?? 'Sign in to make this space yours.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Color(0xFFB8C5DA), fontSize: 16)),
                  const SizedBox(height: 32),
                  if (user != null)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _signOut,
                      icon: _busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.logout_rounded),
                      label: const Text('Sign out'),
                    )
                  else
                    FilledButton(
                      onPressed: () => Navigator.of(context)
                          .popUntil((route) => route.isFirst),
                      child: const Text('Sign in'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
