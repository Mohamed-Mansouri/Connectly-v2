# Feed module

`module_entry.dart` connects the shell to `presentation/feed_screen.dart`. The feed now uses SQLite on the phone; no API or network is needed.

## Working features

- Create text posts (1–3,000 trimmed characters) and delete your own posts with confirmation.
- Read a chronological feed with Connections, Friends, and Following filters. Your own posts appear in every filter.
- Manage follows/friend requests in the People bottom tab (see `../discovery/README.md`). The Feed top People button has been removed. Empty-feed Find people switches tabs.
- React with Like, Love, Celebrate, or Insightful. One reaction per person/post; choosing another replaces it. Remove reaction clears only your own selection.
- Tap a post's reaction counts to see who reacted (you first, then by name), filterable by reaction type.
- Comment on any visible post (1–1,000 trimmed characters) from the Comment button. Comment authors can delete their comments; post authors can delete any comment on their post. The card shows the comment count.
- Pull to refresh and load older posts with a stable timestamp/ID cursor, 20 at a time.
- Guests see a sign-in invitation. Empty, loading, service-error, and busy states have dedicated UI.

## Source and data flow

`FeedScreen -> FeedController / FeedRepository -> SqliteFeedRepository -> connectly_local.db`

| Layer | Files |
| --- | --- |
| Views | `presentation/feed_screen.dart`, `create_post_sheet.dart`, `post_card.dart`, `post_sheets.dart` (comments, reactors), `feed_widgets.dart` |
| State | `application/feed_controller.dart`: refresh/filter, cursor loading, publishing results, reaction/delete busy states, stale request protection. |
| Contracts | `domain/feed_models.dart`: posts, pages, people, repository interface, safe errors. |
| Data | `data/sqlite_feed_repository.dart`: bound SQLite queries, transactions, ownership, visibility, and reactions. |
| Initialization | `lib/app/local_data_scope.dart` supplies the shared phone database for the signed-in account. |
| Schema | `lib/shared/data/local_schema.dart`: `posts`, `follows`, `friendships`, `post_reactions`, `post_comments` (schema version 5). |

## Storage and visibility

SQLite persists posts, connections, and reactions on this phone. The repository uses the signed-in account for authorship and checks connections before returning or reacting to a post. People lists other accounts created on this phone, without exposing password fields. Switch accounts to demonstrate both sides of a friendship or follow.

Displayed pages live in memory and reload from SQLite after restart, including offline. Hive has auth preferences and messaging drafts/pending sends, but no separate feed cache. Post composer text survives a failed publication while the sheet is open; closing discards it. Revisiting Feed or pulling down refreshes local records, including connection changes in People. Separate phones do not synchronize data.

## Verification and remaining work

Run `flutter test` and `flutter analyze`. `test/local/sqlite_repositories_test.dart` exercises real SQLite feed visibility, friend requests, follows, reactions, ownership, and tied-timestamp pagination. The old HTTP client/backend scripts remain reference code; they are not needed for the local presentation.

Images/uploads, editing posts, persistent drafts/caches, comment replies/editing, notifications, and semantic recommendation ranking remain future work. The advanced demonstration will compare embedding/interaction ranking with the current chronological feed.

## Hashtags, mentions and search

Posts may contain `#tags` (letters, digits, `_`; stored lower case) and `@handles` (the email part before `@`, e.g. `@amal`). `data/post_index.dart` saves them in `post_tags` / `post_mentions` (schema v7) inside the create transaction; triggers copy bodies into the `posts_fts` full-text table (FTS4, or FTS5, or a substring fallback when neither module exists). `PostSearchScreen` (search icon, or tapping a tag/mention) combines `#tag`, `@handle` and word-prefix filters with the normal Connections visibility rule, ranks word matches (exact 3, prefix 1, then newest), highlights them, and shows the top 30-day hashtags when empty. `SuggestionBar` completes `#`/`@` words in the composer and search box.

## Post photos

The composer can attach one photo (gallery or camera, optional crop/rotate via `shared/presentation/photo_crop_screen.dart`). It is resized off the UI thread to at most 1280 px on the longest side (JPEG) and stored in `post_images` (schema v8) in the create transaction. Feed queries only join `width`/`height`; `PostImageView` loads bytes on demand through `postImage(postId)`, which checks visibility and keeps a 30-photo memory cache. Tapping a photo opens a zoomable viewer. A caption is still required because `posts.body` must be 1–3,000 characters.
