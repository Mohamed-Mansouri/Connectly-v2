# Connectly v2 — local presentation

Connectly now runs entirely on the phone using **SQLite through `sqflite`**, with **Hive** for preferences and messaging drafts. No .NET API, Turso connection, internet connection, database token, or port forwarding is needed to use the app.

On startup, the app adds six clearly labeled, fictional **Demo** accounts with shared map locations near Ariana center and ESPRIT Charguia. Your own accounts, pins, and friendships are preserved on subsequent launches. Earlier cloud accounts/posts/messages are not imported; the Turso database is unchanged. Separate phones have separate databases and do not exchange messages.

## Working features

- Registration, login/logout, offline session restoration, Profile, and guest navigation.
- Text posts, friends/following filters, friend requests, four reactions, and own-post deletion.
- Direct/group text chats, conversation history, unread counts, pagination, saved drafts, and retry deduplication.
- People opens on an offline Ariana map showing shared locations within 1 km of your saved pin. Search, friend requests, friends/following, list mode, and wider distance filters remain available. Profile supports name, email, bio, photo, and location editing. Comments, media posts, and advanced features remain planned.

## Storage and source map

| Data | Storage | Source |
| --- | --- | --- |
| Accounts, password hashes, sessions, posts, follows, friendships, reactions, conversations, members, messages | `connectly_local.db` in the phone's app database directory | [schema](lib/shared/data/local_schema.dart), [opening/versioning](lib/shared/data/local_database.dart) |
| Remembered email | Hive `auth_preferences` / `remembered_email` | [preferences](lib/features/auth/data/login_preferences.dart) |
| Account/conversation drafts and pending sends | Hive `messaging_local` / `<userId>:<conversationId>` | [chat store](lib/features/messaging/data/chat_local_store.dart) |
| Current local-session token | Platform secure storage, `connectly_local_auth_session` | [session store](lib/features/auth/data/auth_session_store.dart) |
| Short bio and profile photo | `user_profiles` in the phone's SQLite database | [profile repository](lib/features/auth/data/profile_repository.dart) |

`main.dart -> LocalAppLoader -> LocalDatabase -> SqliteAuthRepository / SqliteFeedRepository / SqliteMessagingRepository`

[LocalDataScope](lib/app/local_data_scope.dart) supplies the SQLite feature repositories to all routes. Existing screens/controllers keep their repository interfaces. Passwords use salted PBKDF2-SHA256 hashes; only a token hash is stored in SQLite. Local session validation needs no network.

The old `backend/` and `*_api.dart` implementations remain as reference and are not selected by the local app. Their HTTP unit tests are retained; local integration tests exercise actual SQLite.

## Run on the phone

```powershell
flutter pub get
flutter devices
flutter run -d <device-id>
```

USB debugging or Android Wireless debugging can be used to install/debug. Wireless debugging needs pairing and a connection address; see [Android instructions](https://developer.android.com/tools/adb#connect-to-a-device-over-wi-fi). Wi-Fi is only needed for wireless installation/debugging; the installed app uses its local database. Do not pass an `API_BASE_URL` or run the API for this version.

```powershell
flutter test
flutter analyze
flutter build apk --debug
```

The APK is `build/app/outputs/flutter-apk/app-debug.apk`. The presentation targets Android; SQLite repository tests use `sqflite_common_ffi` on this PC.

## Presentation on one phone

1. Create Alice, publish a post, then sign out in Profile.
2. Create Bob. Open the People tab, follow Alice; view/react to her post and send a friend request.
3. As Bob, start a direct chat with Alice and send a message.
4. Sign out, sign in as Alice, accept Bob's request, read his message, and reply.
5. Switch back to Bob to show the reply/unread state. Restart to demonstrate persistence.
6. For a group, create a third local account, connect with it, and select two people when creating the group.
7. In People, use **Set my location** to save a pin near Ariana center or ESPRIT Charguia (or use your phone's GPS). The discovery map opens first and shows shared pins within 1 km. Tap a demo person's marker and **Add friend**. Sign out, sign in as that demo person, and accept the request. The discovery map selects existing pins; manual placement is only in the separate location setup sheet.

### Demo account sign-in

All six fictional profiles use the password **`12345678`**. Their local email addresses are `demo.amal@connectly.invalid`, `demo.sami@connectly.invalid`, `demo.ines@connectly.invalid` (Ariana center), and `demo.nour@connectly.invalid`, `demo.youssef@connectly.invalid`, `demo.meriem@connectly.invalid` (ESPRIT Charguia). They start without friendships; requests can be accepted after switching accounts. Existing demo passwords are updated on the next app launch; locations and relationships are not reset at startup.

The map covers **Ariana city** (36.84–36.90°N, 10.15–10.21°E), with bundled OpenStreetMap geometry and visible attribution. It does not download tiles. Saved locations are optional per-account SQLite rows, with a hide/remove option and no background tracking. Pins represent accounts on this phone, not live nearby devices. Without your own saved location, the map shows all shared pins and asks you to set yours before calling anyone nearby. Existing pins outside Ariana stay saved and can be repositioned using Edit my pin. See [map credits/source](assets/maps/README.md).

See [UI_GUIDE.md](UI_GUIDE.md) for views and storage details and [WHATS_NEXT.md](WHATS_NEXT.md) for remaining work. Use [BRANCHES.md](BRANCHES.md) for Git workflow.
