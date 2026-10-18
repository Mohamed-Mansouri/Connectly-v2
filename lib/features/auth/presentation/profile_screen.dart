import 'package:flutter/material.dart';

import '../../../shared/presentation/empty_state.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: const EmptyState(
        icon: Icons.account_circle_outlined,
        title: 'Make it yours',
        message: 'Your account and profile will appear here.',
      ),
    );
  }
}
