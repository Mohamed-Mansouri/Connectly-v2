import 'package:flutter/material.dart';

import 'connectly_theme.dart';

class ConnectlyApp extends StatelessWidget {
  const ConnectlyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Connectly',
      debugShowCheckedModeBanner: false,
      theme: ConnectlyTheme.dark,
      home: const Scaffold(
        body: Center(child: Text('Connectly baseline')),
      ),
    );
  }
}
