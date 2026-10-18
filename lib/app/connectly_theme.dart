import 'package:flutter/material.dart';

class ConnectlyTheme {
  static const navy = Color(0xFF1B2B4B);
  static const surface = Color(0xFF253657);
  static const yellow = Color(0xFFFFD21A);

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: navy,
        colorScheme: const ColorScheme.dark(
          primary: yellow,
          onPrimary: Colors.black,
          surface: navy,
          onSurface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: navy,
          foregroundColor: Colors.white,
          centerTitle: false,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: surface,
          indicatorColor: yellow,
          labelTextStyle: WidgetStateProperty.all(
            const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
      );
}
