import 'package:flutter/material.dart';

import '../features/auth/module_entry.dart';
import '../features/discovery/module_entry.dart';
import '../features/feed/module_entry.dart';
import '../features/messaging/module_entry.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  static const _screens = [
    FeedModule(),
    DiscoveryModule(),
    MessagingModule(),
    AuthModule(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppTabScope(
          select: (index) => setState(() => _selectedIndex = index),
          child: IndexedStack(index: _selectedIndex, children: [
            for (var index = 0; index < _screens.length; index++)
              TickerMode(
                  enabled: index == _selectedIndex, child: _screens[index]),
          ])),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Feed'),
          NavigationDestination(
              icon: Icon(Icons.people_outline), label: 'People'),
          NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline), label: 'Chats'),
          NavigationDestination(
              icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }
}

class AppTabScope extends InheritedWidget {
  const AppTabScope({required this.select, required super.child, super.key});
  final ValueChanged<int> select;
  static void people(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppTabScope>()?.select(1);
  @override
  bool updateShouldNotify(AppTabScope oldWidget) => false;
}
