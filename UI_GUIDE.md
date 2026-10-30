# UI and local data guide

## Current architecture — 2026-10-26

The app uses SQLite on the phone through `sqflite`. Hive holds preferences and message drafts/pending sends. Authentication, feed, and messaging work without a backend. New installations start empty. Accounts and records on another phone or in the old Turso database do not appear here.

`Screen -> controller / repository interface -> SQLite repository -> connectly_local.db`

[LocalAppLoader](lib/app/local_app_loader.dart) opens the database, initializes email preferences, creates the local authentication controller, and restores a saved local session. Failure to open the database shows a storage error and Retry. [LocalDataScope](lib/app/local_data_scope.dart) supplies the shared database to feature repositories. No runtime screen constructs an HTTP API client.

## Views and actions

| View | Working behavior |
| --- | --- |
| Login | Email/password, show/hide password, remembered email, sign in, create account, guest access. The subtitle explains that accounts/data stay on this phone. Validation, busy states, autofill, responsive scrolling, and a safe-area footer remain. |
| Create account | Name/email/password/confirmation. Creates an account in local SQLite and signs in. Names require 2–80 characters, valid emails at most 254, passwords 8–128. Email is trimmed/lowercased; passwords are preserved exactly. |
| Profile | Displays the current local user's name/email; Sign out returns to Login. Guests get a sign-in action. Editing remains planned. |
| Feed | Connections/Friends/Following filters, chronological posts, composer, reaction totals, pull to refresh, and pagination. Empty-feed Find people switches to the People tab. Own posts appear in every filter. |
| Create post | Trimmed text, 1–3,000 characters; inserts into SQLite. Failure preserves the open sheet's text. Closing discards this in-memory post draft. Own-post deletion requires confirmation and cascades reactions. |
| People | Bottom tab replacing Nearby. Name search, Discover/Friends/Friend requests/Following filters, list/map modes, and connection actions in one place. Follow/unfollow is one-way; friendship requires recipient acceptance. Tap map markers to select people and reveal the same actions. Switch accounts to demonstrate both sides. |
| Your map pin | Tap the offline Ariana map or request a foreground GPS fix; Save explicitly. Share/hide/remove the pin. Denied permission, timeout, disabled location, and outside-coverage fixes leave manual placement available. No continuous tracking. |
| Proximity | Optional 1/5/10/25 km filters measure straight-line distance from the account's saved pin and sort nearest first. Unlocated/hidden accounts remain searchable in Any distance list mode but are excluded from radius matches and the map. |
| Post reactions | Like, Love, Celebrate, Insightful; one reaction per account/post. Replace/remove changes local SQLite rows. Comments are deferred. |
| Chats | Member conversations, title search, last-message previews, unread counts, refresh, and New conversation. Guest access does not query account data. |
| New conversation | Select friends/followed accounts on this phone: one for direct chat, or 2–19 others plus a group title. Direct pairs reopen their existing chat. |
| Conversation | Incoming/outgoing text, sender names in groups, dates/times, earlier history, keyboard-aware composer, send/retry states, and member list. Messages require 1–4,000 trimmed characters. |

The navy/yellow theme and Urbanist type remain. Feed/Chats/Profile keep their state while switching tabs using `IndexedStack`. Chats pauses periodic refresh while hidden/backgrounded. Its existing 10-second inbox and 5-second conversation refreshes now read the local database; they send no HTTP requests. Return to Chats or pull to refresh after switching accounts.

## SQLite responsibilities

[local_schema.dart](lib/shared/data/local_schema.dart) defines the original tables and version 2 location table. [LocalDatabase](lib/shared/data/local_database.dart) opens `connectly_local.db` in `getDatabasesPath()`, enables foreign keys, and upgrades version 1 by adding `user_locations` without replacing existing records. Creation/upgrades are transactional; repositories use bound query arguments and transactions for related writes. SQLite stores timestamps as UTC text and reaction/unread counts as integers.

| Tables | Repository / functions |
| --- | --- |
| `users`, `auth_sessions` | [SqliteAuthRepository](lib/features/auth/data/sqlite_auth_repository.dart): `signUp`, `signIn`, `currentUser`, `signOut`. |
| `posts`, `follows`, `friendships`, `post_reactions` | [SqliteFeedRepository](lib/features/feed/data/sqlite_feed_repository.dart): load/create/delete/react, people, follow, friendship. |
| `user_locations` plus connections | [SqlitePeopleRepository](lib/features/discovery/data/people_repository.dart): search/filter with visible-location joins, Haversine distances, `saveLocation`, `removeLocation`. The current account can still use its hidden pin as its distance origin. Locations are SQLite data, not Hive cache. |
| `conversations`, `conversation_members`, `messages` | [SqliteMessagingRepository](lib/features/messaging/data/sqlite_messaging_repository.dart): conversations/contacts/create/members, history/send/read. |

Feed visibility is still own posts plus followed authors/accepted friends. Chat history/send/read operations check membership. Authors/senders come from the currently authenticated account's repository. Messages are unique by conversation/sender/client ID so retrying does not duplicate them. Pagination uses timestamp/ID cursors for posts and integer sequences for messages. Unread cursors cannot advance past existing messages.

The People tab refreshes on activation or pull/Refresh. Feed refreshes when revisited after connection changes. [ArianaMap](lib/features/discovery/presentation/ariana_map.dart) renders [bundled ODbL geometry](assets/maps/README.md) with Flutter Map and no tile provider/network access. Coverage is Ariana city (36.84–36.90°N, 10.15–10.21°E); map pins are the saved positions of accounts on this phone. Old pins outside the current map remain saved, with a prompt to edit them.

## Sessions and Hive

Passwords are salted PBKDF2-SHA256 hashes at 120,000 iterations, defined in [LocalPasswords](lib/features/auth/data/local_passwords.dart). Secure storage holds the opaque token under `connectly_local_auth_session`; SQLite holds its SHA-256 hash and seven-day expiry. Startup checks SQLite locally, so valid sessions restore offline. This separate key does not reuse the old cloud token. Logout clears the saved token and removes its local session.

| Hive box / key | Content and lifecycle |
| --- | --- |
| `auth_preferences` / `remembered_email` | Optional email. Loaded on Login; saved before submission/guest entry when opted in; unchecking deletes it. Logout retains it. No password/token is stored here. |
| `messaging_local` / `<userId>:<conversationId>` | JSON draft and outbox entries `{ clientId, body, createdAt }`. Draft saves are debounced 250 ms and queued on leaving. A pending send is saved before its SQLite insert, then removed when confirmed. Empty records are deleted. Restored pending items have an explicit Retry action. |

Hive records remain account-scoped after logout. If Hive cannot open, temporary memory keeps chat usable with a notice; subsequent write failures retain pending text and stop that send. Full message history is in SQLite, so it remains available offline after restart. Post drafts remain in memory. There is no network synchronization between phones.

## Verification and presentation

The local test suite uses a real SQLite engine to check empty initialization, foreign keys, authentication/passwords/sessions, friends/follows, reactions, ownership, group membership, unread counts, idempotent sends, pagination, and reopening a database file. [local_app_test.dart](test/local/local_app_test.dart) renders the default Feed/Chats with HTTP creation blocked.

Run `flutter test` and `flutter analyze`. The original API mock tests remain for reference, but the app defaults to SQLite. Follow the one-phone account-switching demonstration in [README.md](README.md). Cloud data is not imported and no demo records are seeded.
