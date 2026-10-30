# Feed module

`module_entry.dart` connects the shell to `presentation/feed_screen.dart`. The feed now uses SQLite on the phone; no API or network is needed.

## Working features

- Create text posts (1–3,000 trimmed characters) and delete your own posts with confirmation.
- Read a chronological feed with Connections, Friends, and Following filters. Your own posts appear in every filter.
- Manage follows/friend requests in the People bottom tab (see `../discovery/README.md`). The Feed top People button has been removed. Empty-feed Find people switches tabs.
- React with Like, Love, Celebrate, or Insightful. One reaction per person/post; choosing another replaces it. Remove reaction clears only your own selection.
- Pull to refresh and load older posts with a stable timestamp/ID cursor, 20 at a time.
- Guests see a sign-in invitation. Empty, loading, service-error, and busy states have dedicated UI. Comments have no UI or endpoints in this version.

## Source and data flow

`FeedScreen -> FeedController / FeedRepository -> SqliteFeedRepository -> connectly_local.db`

| Layer | Files |
| --- | --- |
| Views | `presentation/feed_screen.dart`, `create_post_sheet.dart`, `post_card.dart`, `feed_widgets.dart` |
| State | `application/feed_controller.dart`: refresh/filter, cursor loading, publishing results, reaction/delete busy states, stale request protection. |
| Contracts | `domain/feed_models.dart`: posts, pages, people, repository interface, safe errors. |
| Data | `data/sqlite_feed_repository.dart`: bound SQLite queries, transactions, ownership, visibility, and reactions. |
| Initialization | `lib/app/local_data_scope.dart` supplies the shared phone database for the signed-in account. |
| Schema | `lib/shared/data/local_schema.dart`: `posts`, `follows`, `friendships`, `post_reactions`. |

## Storage and visibility

SQLite persists posts, connections, and reactions on this phone. The repository uses the signed-in account for authorship and checks connections before returning or reacting to a post. People lists other accounts created on this phone, without exposing password fields. Switch accounts to demonstrate both sides of a friendship or follow.

Displayed pages live in memory and reload from SQLite after restart, including offline. Hive has auth preferences and messaging drafts/pending sends, but no separate feed cache. Post composer text survives a failed publication while the sheet is open; closing discards it. Revisiting Feed or pulling down refreshes local records, including connection changes in People. Separate phones do not synchronize data.

## Verification and remaining work

Run `flutter test` and `flutter analyze`. `test/local/sqlite_repositories_test.dart` exercises real SQLite feed visibility, friend requests, follows, reactions, ownership, and tied-timestamp pagination. The old HTTP client/backend scripts remain reference code; they are not needed for the local presentation.

Images/uploads, editing posts, persistent drafts/caches, comments, notifications, and semantic recommendation ranking remain future work. The advanced demonstration will compare embedding/interaction ranking with the current chronological feed.
