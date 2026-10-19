# Baseline UI guide

## Home screen: `lib/app/home_screen.dart`

The first screen shows the Connectly name, a short description, and **Open modules**. `Scaffold` supplies the page frame, `AppBar` carries the title, and `SafeArea` keeps content clear of system UI. `SingleChildScrollView`, `ConstrainedBox`, and `Padding` keep the layout usable on small phones and wide Chrome windows. The button pushes `AppShell`; system back returns Home. There is no login or data request here.

## Navigation shell: `lib/app/app_shell.dart`

`NavigationBar` has Feed, Nearby, Chats, and Profile destinations. `IndexedStack` keeps tab state while switching. Each destination loads one `module_entry.dart` file. A feature branch replaces its own entry's placeholder with its screen; no other feature file needs editing. The shell owns navigation only and makes no API calls.

## Empty module screen: `lib/shared/presentation/module_placeholder_screen.dart`

The four tabs on `main` show a titled `Scaffold` and an `EmptyState` with an icon and message. The message tells developers the module is ready for work. These are navigation placeholders, not implemented feature screens or fake content.

## Shared components

- `EmptyState` centers an icon, title, and message with a maximum width. It can later represent a real empty response; loading and error states need separate UI.
- `ConnectlyTheme` supplies the dark navy and yellow app colors and styles the navigation bar.
- `ConnectlyApp` creates `MaterialApp` and selects Home as the start screen. `main.dart` only calls `runApp`.

For each future screen, document its visible widgets, user actions, navigation, SQLite records or Hive values, and loading, empty, and error states here. The first tier accesses local storage through feature repositories. Include restart persistence and local test-account behavior when documenting a completed flow. A visual control should have real behavior before being presented as a working feature.
