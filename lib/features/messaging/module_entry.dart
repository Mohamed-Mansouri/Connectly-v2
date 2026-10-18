import 'package:flutter/material.dart';

import '../../shared/presentation/module_placeholder_screen.dart';

class MessagingModule extends StatelessWidget {
  const MessagingModule({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholderScreen(
      title: 'Chats',
      icon: Icons.forum_outlined,
    );
  }
}
