import 'package:flutter/material.dart';

import 'connectly_theme.dart';
import 'home_screen.dart';

class ConnectlyApp extends StatelessWidget {
  const ConnectlyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Connectly',
      debugShowCheckedModeBanner: false,
      theme: ConnectlyTheme.dark,
      home: const HomeScreen(),
    );
  }
}
