# Connectly v2

This is the independent Flutter repository for the four-person university project. The `main` branch is a small shared baseline: a home screen, bottom navigation, and four empty module entry points. It has no login, posts, map, messages, or API implementation.

## Open the app

Flutter and Dart were not found on this PC's PATH during the last check. After installing Flutter, open this repository folder in VS Code and run:

    flutter doctor
    flutter pub get
    flutter analyze
    flutter test
    flutter run -d chrome

Chrome was detected on this PC. The copied native platform runners still have identifiers from the original app; set a distinct Android application ID before installing both apps on one device. See the [Flutter setup guide](https://docs.flutter.dev/install/quick).

## Branches

| Branch | Purpose |
| --- | --- |
| `main` | Home, navigation, shared theme, and empty module entry points. |
| `auth` | Account and profile screen, then authentication work. |
| `feed` | Feed screen, then posts and recommendations. |
| `discovery` | Nearby screen, then map and proximity matching. |
| `messaging` | Chats screen, then conversations and voice features. |
| `navigation` | Shared navigation checks and future route work. |
| `archive/sprint-0` | The earlier combined preview and its original commits, preserved for reference. |

Each feature branch starts from the same `main` baseline. The four `lib/features/*/module_entry.dart` files are small contracts used by the navigation shell. A member changes only their entry file and adds their own screens under their feature folder. Other tabs keep working as placeholders until their branches are merged.

Read [BRANCHES.md](BRANCHES.md) for checkout and merge steps, [SPRINT_00.md](SPRINT_00.md) for progress, [WHATS_NEXT.md](WHATS_NEXT.md) for feature scope, and [UI_GUIDE.md](UI_GUIDE.md) for the baseline screens and widgets.
