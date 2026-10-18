import 'package:flutter/material.dart';

import '../../shared/presentation/module_placeholder_screen.dart';

class AuthModule extends StatelessWidget {
  const AuthModule({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholderScreen(
      title: 'Profile',
      icon: Icons.person_outline,
    );
  }
}
