# Feed module

The `feed` branch includes `main`'s working authentication. `module_entry.dart` connects the shell to the live feed through `presentation/feed_screen.dart`.

## Working features

- Create text posts (1–3,000 trimmed characters) and delete your own posts with confirmation.
- Read a chronological feed with Connections, Friends, and Following filters. Your own posts appear in every filter.
- Find registered people by name; follow/unfollow independently of friendship.
- Send/cancel friend requests, accept/decline incoming requests, and remove friends. Only accepted friendship grants feed access.
- React with Like, Love, Celebrate, or Insightful. One reaction per person/post; choosing another replaces it. Remove reaction clears only your own selection.
- Pull to refresh and load older posts with a stable timestamp/ID cursor, 20 at a time.
- Guests see a sign-in invitation. Empty, loading, service-error, and busy states have dedicated UI. Comments have no UI or endpoints in this version.

## Source and data flow

`FeedScreen / PeopleScreen -> FeedController / FeedRepository -> FeedApi -> .NET FeedController / FeedService -> Turso`

| Layer | Files |
| --- | --- |
| Views | `presentation/feed_screen.dart`, `create_post_sheet.dart`, `post_card.dart`, `people_screen.dart`, `feed_widgets.dart` |
| State | `application/feed_controller.dart`: refresh/filter, cursor loading, publishing results, reaction/delete busy states, stale request protection. |
| Contracts | `domain/feed_models.dart`: posts, pages, people, repository interface, safe errors. |
| HTTP | `data/feed_api.dart`: current bearer token from `AuthController.sessionToken`, JSON and timeouts; no database credentials. |
| Backend | `backend/Controllers/FeedController.cs`, `backend/Services/FeedService.cs`, `backend/Models/FeedModels.cs` |
| Schema | `backend/migrations/002_feed.sql`: `posts`, `follows`, `friendships`, `post_reactions`. |

## Storage and visibility

Turso persists posts, connections, and reactions across devices. The server determines authorship from the authenticated account and checks connections before returning or reacting to a post. The People directory exposes names and IDs, without emails or password fields.

Feed pages and connection results are held in memory only. Refresh failures can leave already loaded posts visible with an error; restarting offline does not restore a cached feed. Hive has auth email preferences and messaging drafts/pending sends, but no feed cache. Post composer text survives a failed publication while the sheet is open; closing it or restarting discards the draft. There is no live push or background feed sync: pull down to fetch other people's new posts, reactions, and requests. Returning from People refreshes the feed.

## Verification and remaining work

Flutter analysis passed, all 31 app tests passed, the .NET build succeeded, and the live feed integration script passed on 2026-10-24. Run `backend/tests/Test-Feed.ps1` against the updated API; its default test port is 8788. It creates temporary accounts and cleans up only their records. See [backend setup](../../../backend/README.md#feed-and-connections-on-feed).

Images/uploads, editing posts, persistent drafts/caches, comments, notifications, and semantic recommendation ranking remain future work. The advanced demonstration will compare embedding/interaction ranking with the current chronological feed.
