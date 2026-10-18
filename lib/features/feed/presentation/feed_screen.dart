import 'package:flutter/material.dart';

import '../../../shared/presentation/empty_state.dart';

class FeedScreen extends StatelessWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Feed')),
      body: const EmptyState(
        icon: Icons.dynamic_feed_outlined,
        title: 'Your feed starts here',
        message: 'Posts from people you connect with will appear here.',
      ),
    );
  }
}
