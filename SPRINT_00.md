# Sprint 0: shared baseline and branches

Date: 18 October 2026.

## Goal

Give the team a small app they can navigate, with independent starting branches for auth, feed, discovery, messaging, and shared navigation.

## Achieved

- [x] Preserve the previous combined preview on `archive/sprint-0`.
- [x] Keep `main` limited to Home, four-tab navigation, shared styling, and module placeholders.
- [x] Create sibling `auth`, `feed`, `discovery`, `messaging`, and `navigation` branches.
- [x] Give each feature branch a starting screen in its own folder.
- [x] Document the views and branch workflow.
- [x] Install Flutter, Dart, VS Code extensions, Android Studio, and Android SDK 36 on this PC.
- [x] Resolve packages, analyze the source, and build the web version.
- [x] Build, install, and launch the Android debug app on a physical phone.
- [x] Give v2 a distinct Android app ID, `com.example.connectly_v2`.

## Verification

`flutter doctor -v` reported no issues. `flutter analyze` reported no issues. `flutter build web` passed, and `flutter run` built and launched the app on an Android 11 phone. The navigation widget test is on the `navigation` branch and can be run with `flutter test` there.

The advanced features and API endpoints in [WHATS_NEXT.md](WHATS_NEXT.md) remain future work.
