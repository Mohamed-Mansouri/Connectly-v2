# Connectly v2

This is the new Flutter repository for our four-person university project. Open **`C:\Users\Med\Documents\Connectly-v2`** in VS Code. The older project in `C:\Users\Med\Documents\Connectly` is separate.

The `main` branch is the shared baseline. It has a Home screen, navigation, theme, and empty module entry points. Login, posts, maps, messaging, APIs, and advanced features are planned work, not implemented behavior.

## Project views

The flow on `main` is **Home -> Open modules -> Feed / Nearby / Chats / Profile**. Android's Back button returns from the module tabs to Home.

| View | What it shows now | Main source file |
| --- | --- | --- |
| Home | Connectly welcome text and the **Open modules** button. | `lib/app/home_screen.dart` |
| Module navigation | Four bottom tabs. Switching tabs preserves their state. | `lib/app/app_shell.dart` |
| Feed | An empty starting point for posts. | `lib/features/feed/module_entry.dart` |
| Nearby | An empty starting point for discovery and a future map. | `lib/features/discovery/module_entry.dart` |
| Chats | An empty starting point for conversations. | `lib/features/messaging/module_entry.dart` |
| Profile | An empty starting point for accounts and profile. | `lib/features/auth/module_entry.dart` |

The four empty tabs on `main` use one shared `ModulePlaceholderScreen`. Each feature branch replaces **only its own tab** with a starting screen in its `presentation` folder. For example, `git switch discovery` shows the Nearby starting screen while the other tabs remain placeholders. These branch screens still have no API data. See [UI_GUIDE.md](UI_GUIDE.md) for the widgets and navigation behavior.

## Branches

| Branch | Owner's starting work |
| --- | --- |
| `main` | Shared Home, theme, navigation, and module entry contracts. |
| `auth` | Profile screen; future sign-up, login, and face verification with liveness. |
| `feed` | Feed screen; future posts and personalized ranking. |
| `discovery` | Nearby screen; future map and live proximity matching. |
| `messaging` | Chats screen; future conversations and translated voice messages. |
| `navigation` | Shared navigation test and future routing work. |
| `archive/sprint-0` | Earlier combined preview and supplied design screenshots. |

Run `git branch --list` to see the branches and `git switch auth` (or another branch name) to inspect one module. Switching branches changes the files in the open folder. Read [BRANCHES.md](BRANCHES.md) before merging work, and [WHATS_NEXT.md](WHATS_NEXT.md) for planned endpoints and advanced features.

## Run from the VS Code terminal

1. In VS Code, choose **File > Open Folder** and select `C:\Users\Med\Documents\Connectly-v2`. Open **Terminal > New Terminal**. If this terminal was open before Flutter was installed, restart VS Code so it sees the updated PATH.
2. In the PowerShell terminal, prepare and check the project:

   ```powershell
   cd C:\Users\Med\Documents\Connectly-v2
   flutter doctor
   flutter pub get
   flutter devices
   ```

3. Keep USB debugging enabled and your phone connected. Use the Android device ID shown by `flutter devices`:

   ```powershell
   flutter run -d ae64b3ca
   ```

   `ae64b3ca` is the ID detected for the phone used during setup; replace it if `flutter devices` shows a different ID. Approve any USB debugging prompt on the phone. The Android app ID is `com.example.connectly_v2`, so it can be installed beside the older app.

4. To run on this PC in Chrome instead, use `flutter run -d chrome`. Native Windows is also available with `flutter run -d windows`.

While `flutter run` is active in the terminal, press `r` for hot reload, `R` for hot restart, and `q` to stop. For a quick code check, run `flutter analyze`. The navigation widget test lives on the `navigation` branch:

```powershell
git switch navigation
flutter pub get
flutter test
git switch main
```

## Setup verified on this PC

Flutter 3.47.7, Dart 3.13.5, the Flutter/Dart VS Code extensions, Android Studio, and Android SDK 36 are installed. `flutter doctor -v` reported no issues. `flutter analyze` and the web build passed. The Android debug app built, installed, and launched on the connected Android 11 phone. The first build may take longer while Gradle downloads its tools.

See [SPRINT_00.md](SPRINT_00.md) for the completed baseline and [UI_GUIDE.md](UI_GUIDE.md) for each UI component.
