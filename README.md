# Connectly v2 — local presentation

Connectly now runs entirely on the phone using **SQLite through `sqflite`**, with **Hive** for preferences and messaging drafts. No .NET API, Turso connection, internet connection, database token, or port forwarding is needed to use the app.

The database starts **empty**, as requested. Create accounts on this phone. Earlier cloud accounts/posts/messages are not imported; the Turso database is unchanged. Separate phones have separate databases and do not exchange messages.

## Working features

- Registration, login/logout, offline session restoration, Profile, and guest navigation.
- Text posts, friends/following filters, friend requests, four reactions, and own-post deletion.
- Direct/group text chats, conversation history, unread counts, pagination, saved drafts, and retry deduplication.
- People combines name search, friend requests, friends/following, and an offline Ariana map with saved pins and proximity filters. Comments, media, profile editing, and advanced features remain planned.

## Storage and source map

| Data | Storage | Source |
| --- | --- | --- |
| Accounts, password hashes, sessions, posts, follows, friendships, reactions, conversations, members, messages | `connectly_local.db` in the phone's app database directory | [schema](lib/shared/data/local_schema.dart), [opening/versioning](lib/shared/data/local_database.dart) |
| Remembered email | Hive `auth_preferences` / `remembered_email` | [preferences](lib/features/auth/data/login_preferences.dart) |
| Account/conversation drafts and pending sends | Hive `messaging_local` / `<userId>:<conversationId>` | [chat store](lib/features/messaging/data/chat_local_store.dart) |
| Current local-session token | Platform secure storage, `connectly_local_auth_session` | [session store](lib/features/auth/data/auth_session_store.dart) |

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
7. In People, place a different map pin for each account. Switch accounts, select Map, choose a distance, and tap a person's marker to follow/add a friend. Only shared pins appear. GPS is optional; manually placed pins also work offline.

The map covers **Ariana city** (36.84–36.90°N, 10.15–10.21°E), with bundled OpenStreetMap geometry and visible attribution. It does not download tiles. Saved locations are optional per-account SQLite rows, with a hide/remove option and no background tracking. Pins represent accounts on this phone, not live nearby devices. Existing pins outside Ariana stay saved and can be repositioned using Edit my pin. See [map credits/source](assets/maps/README.md).

See [UI_GUIDE.md](UI_GUIDE.md) for views and storage details and [WHATS_NEXT.md](WHATS_NEXT.md) for remaining work. Use [BRANCHES.md](BRANCHES.md) for Git workflow. No demo data is seeded.
