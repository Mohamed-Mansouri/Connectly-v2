import 'package:flutter/material.dart';

import '../../../shared/presentation/empty_state.dart';

class NearbyScreen extends StatelessWidget {
  const NearbyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nearby')),
      body: const EmptyState(
        icon: Icons.map_outlined,
        title: 'Meet people nearby',
        message: 'The nearby map and user cards will appear here.',
      ),
    );
  }
}
