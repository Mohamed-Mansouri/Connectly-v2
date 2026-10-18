import 'package:flutter/material.dart';

import '../../../shared/presentation/empty_state.dart';

class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chats')),
      body: const EmptyState(
        icon: Icons.forum_outlined,
        title: 'Start a conversation',
        message: 'Your group conversations will appear here.',
      ),
    );
  }
}
