# Connectly v2

This is the new Flutter repository for our four-person university project. Open **`C:\Users\Med\Documents\Connectly-v2`** in VS Code. The older project in `C:\Users\Med\Documents\Connectly` is separate.

The `main` branch is the shared baseline, including authentication and the feed: registration, login, secure sessions, account display/logout, guest navigation, text posts, connections, and reactions. Nearby and Chats remain starting screens; their data flows and advanced features are planned work.

The storage direction is **Hive on the device and Turso for shared cloud records**. Authentication uses the **ASP.NET Core .NET 10 API** in [backend/README.md](backend/README.md). Hive stores the optional remembered email; platform secure storage protects the user session. See [WHATS_NEXT.md](WHATS_NEXT.md) for the remaining work.

The app opens login or restores a valid saved session. **Create account** registers a Turso account through the .NET API. Sign in to open the module tabs directly, then select **Profile** to see your account and sign out. **Continue as a guest** opens the tabs without authentication. Keep the backend running and configure the phone's USB reverse mapping as described in [backend/README.md](backend/README.md).

The feed module adds real text posts, friends/following feeds, friend requests, and four reactions. See the [feed module guide](lib/features/feed/README.md) and restart the updated .NET API before testing its endpoints. Comments are deferred.

## Project views

The flow is **Login / Create account / Continue as a guest -> Feed / Nearby / Chats / Profile**. The welcome screen and its **Open modules** step have been removed.

| View | What it shows now | Main source file |
| --- | --- | --- |
| Module navigation | Four bottom tabs. Switching tabs preserves their state. | `lib/app/app_shell.dart` |
| Feed | Text posts, connection filters, reactions, and People. | `lib/features/feed/presentation/feed_screen.dart` |
| Nearby | An empty starting point for discovery and a future map. | `lib/features/discovery/module_entry.dart` |
| Chats | An empty starting point for conversations. | `lib/features/messaging/module_entry.dart` |
| Profile | Account name/email and logout, or a guest sign-in action. | `lib/features/auth/presentation/profile_screen.dart` |

The original four empty tabs used one shared `ModulePlaceholderScreen`; Profile and Feed now load real account and application data. Each feature branch owns its own module entry and presentation files. Branches that have not merged the updated `main` may still show the original Home and placeholders. Nearby and Chats do not yet load stored application records. See [UI_GUIDE.md](UI_GUIDE.md) for the widgets and navigation behavior.

## Branches

| Branch | Owner's starting work |
| --- | --- |
| `main` | Shared authentication, feed, connections, theme, navigation, and module entry contracts. |
| `auth` | Working registration, login, profile display, secure sessions, and logout; profile editing and face verification remain planned. |
| `feed` | Text posts, friends/following feeds, friend requests, and reactions; uploads, comments, and personalized ranking remain planned. |
| `discovery` | Nearby screen; future map and live proximity matching. |
| `messaging` | Chats screen; future conversations and translated voice messages. |
| `navigation` | Shared navigation test and future routing work. |
| `archive/sprint-0` | Earlier combined preview and supplied design screenshots. |

Run `git branch --list` to see the branches and `git switch auth` (or another branch name) to inspect one module. Switching branches changes the files in the open folder. Read [BRANCHES.md](BRANCHES.md) before merging work, and [WHATS_NEXT.md](WHATS_NEXT.md) for local storage responsibilities and advanced feature targets.

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

For the completed auth module, see [views and actions](UI_GUIDE.md#authentication-views), [functions and API flow](UI_GUIDE.md#authentication-functions), and [Hive, secure storage, and cache behavior](UI_GUIDE.md#authentication-storage-and-cache).
