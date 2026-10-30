# What's next — local presentation

## Current direction

Use **sqflite/SQLite on the phone** for relational records and **Hive** for preferences, message drafts, and pending sends. The app's runtime no longer uses the .NET API or Turso. The database starts empty, as requested on 2026-10-26. Existing cloud data is not imported or changed.

## Implemented locally

| Module | Working features | Remaining work |
| --- | --- | --- |
| Accounts | Create account, login/logout, local session restoration, Profile, guest access, remembered email. | Profile editing, password recovery design, advanced face/liveness prototype. |
| Feed | Text posts, chronological pagination, friends/following visibility, friend requests, reactions, own-post deletion. | Editing, images, saved post drafts. Comments remain for later. |
| Messaging | Direct/group text chats, contacts, member history, unread counts, pagination, Hive drafts, idempotent pending-message retries. | Attachments, member management, voice transcription/translation, message search. |
| People / Discovery | Combined friend management and discovery tab; name search, friends/requests/following filters, offline Ariana map, manual/GPS saved pins, visibility/removal, proximity filters, marker selection. | Broader map coverage, shared-device synchronization only if later authorized; advanced interest matching remains planned. |

## Presentation checklist

1. Install the app and create local accounts on the presentation phone.
2. Demonstrate posts, friends/follows, reactions, and messages by signing out and signing in as another local account.
3. Restart to show SQLite persistence and offline session restoration.
4. Present the schema and bound SQLite queries in `lib/shared/data` and each feature's `sqlite_*_repository.dart`.
5. Show Hive's remembered email, scoped message draft, and pending-send recovery.

See [README.md](README.md) for a complete demonstration and [UI_GUIDE.md](UI_GUIDE.md) for views/functions/storage. Separate phones have independent data; same-network Wi-Fi does not synchronize SQLite files. Wi-Fi pairing only enables wireless installation/debugging.

## Development

Keep repository interfaces so screens/controllers stay independent of the storage implementation. Schema version 2 is defined in `lib/shared/data/local_schema.dart`; version 1 upgrades preserve existing data and add optional account pins. Add a versioned migration for later database changes. Run the full Flutter suite, including `test/local`, and `flutter analyze` before merging.

The previous cloud backend, HTTP clients, and integration scripts remain reference code. They are not required for this presentation. Advanced ranking, location matching, and translated voice demonstrations remain planned and can be scoped with the professor before implementation.
