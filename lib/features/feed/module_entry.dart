import 'package:flutter/material.dart';

import '../../shared/presentation/module_placeholder_screen.dart';

class FeedModule extends StatelessWidget {
  const FeedModule({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholderScreen(
      title: 'Feed',
      icon: Icons.dynamic_feed_outlined,
    );
  }
}
