# Next sprint

## First: use the baseline

Flutter, Android Studio, and Android SDK are installed, and the baseline launched on a physical Android phone. Open this repository in VS Code and follow [README.md](README.md) for the exact terminal commands. The expected path is Home -> Open modules -> Feed, Nearby, Chats, and Profile tabs. Each feature branch changes just its tab. The Android application ID is `com.example.connectly_v2`.

Run `flutter test` on the `navigation` branch. As new screens are added, update the UI guide with their widgets, data states, and actions. The old combined preview and its design screenshots remain on `archive/sprint-0`.

## First tier: local SQLite and Hive

**The first tier runs locally on the phone using SQLite and Hive only. It has no backend API or cloud database dependency.** The first storage implementation targets Android.

`Flutter screen -> feature repository -> local SQLite database / Hive boxes`

| Storage | Responsibility | Examples |
| --- | --- | --- |
| **SQLite** through `sqflite` | Relational application records, queried and updated with SQL. | Users, profiles, posts, likes, locations, conversations, members, messages, and attachment metadata. |
| **Hive** | Small local preferences and temporary UI state, accessed by key. | Theme, onboarding completion, selected tab, nearby radius preference, post/message drafts, and current local user ID. |
| **App file storage** | Media files referenced by SQLite records. | Selected images and recorded audio stored in the app's persistent directory. |

SQLite is the source of truth for application records; Hive stores preferences and drafts. See [Flutter's SQLite guide](https://docs.flutter.dev/cookbook/persistence/sqlite) and [Hive's package documentation](https://pub.dev/packages/hive).

Agree on one SQLite schema, common user IDs, table ownership, and versioned migrations across the four modules. Use one shared database connection and namespaced Hive keys. Store salted password hashes for local account checks; Hive's session marker contains only the current user ID.

### Shared storage structure to build

```text
lib/core/storage/
  storage_init.dart       # Initialize SQLite and Hive before opening screens
  app_database.dart       # Open connectly.db; manage schema and migrations
  preferences_store.dart  # Read/write Hive settings and local session state
```

Each feature owns its repository interface and local implementation inside its feature folder, such as `FeedRepository` and `SqliteFeedRepository`. Screens call repository methods such as `createPost()` and `listPosts()`. Shared app initialization supplies the repositories. A later cloud implementation can use the same interfaces; moving or synchronizing existing data will be separate work.

### What the first-tier demonstration must show

- Create and switch between multiple test accounts on one phone.
- Create, read, update, and delete module records in SQLite; save preferences and drafts in Hive.
- Close and reopen the app, then verify that records, settings, and local session state are restored.
- Demonstrate local workflows in airplane mode, including empty, loading, success, and storage-error states.
- Use seeded accounts, stored locations, and local conversations to demonstrate interactions on one device. Each phone has its own records; communication between real devices belongs to a later tier.

## Four member modules

Each member builds the local core module on their branch first. The last column preserves the advanced feature target to develop after the local core. Model processing and any future network services need a separate implementation decision; the first tier uses local repository methods.

| Member | Core module: first tier | Advanced feature and what must actually work |
| --- | --- | --- |
| **1 — Accounts & profile** (`auth`) | Local sign up, login, logout, and profile editing. SQLite: `users`, `profiles`. Hive: current local user ID and onboarding state. Demonstrate validation, duplicate-account rejection, wrong-password rejection, profile updates, and session restoration after restart. | **Face verification with a liveness challenge.** Enroll a face, persist its enrollment data in a future `face_enrollments` table, ask for a random action such as turning the head, and compare a new capture with the enrolled user. Demonstrate success, rejection of another person, rejection of a still photo, and password fallback. [Google's ML Kit documentation](https://developers.google.com/ml-kit/vision/face-detection) explains that detecting a face alone does not identify a person. Scope this as a university prototype. |
| **2 — Posts & feed** (`feed`) | Create, list, edit, and delete local posts; attach locally saved images; like and unlike posts using local test accounts. SQLite: `posts`, `post_media`, `likes`, `interactions`. Hive: unfinished post drafts. Demonstrate ownership of edit/delete actions and persistence after restart. | **Semantic recommendation engine.** Generate embeddings for post content and user interests, store vectors in SQLite, and combine cosine similarity with interaction history and freshness. Add `post_embeddings` and shared `user_interests` data when implementing this feature. Demonstrate different ranked feeds for two local test users, compared with chronological order. |
| **3 — Nearby discovery** (`discovery`) | Display local user cards and stored coordinates on an offline map. Edit local location and visibility settings; filter users by distance. SQLite: `user_locations`, linked to profiles. Hive: selected radius and map-view preferences. Demonstrate distance filtering using seeded coordinates without a network request. | **Live proximity matching.** Change simulated user coordinates, recalculate distances, apply shared-interest and visibility rules, and update matches as users enter or leave the radius. Demonstrate the map and cards updating as two test users move. Real location sharing between phones belongs to a later tier. |
| **4 — Group messaging** (`messaging`) | Create local conversations and groups; add/remove members; save, view, and delete messages and local attachments. SQLite: `conversations`, `conversation_members`, `messages`, `attachments`. Hive: message drafts. Switch local accounts to demonstrate conversation history and membership rules on one phone. | **Multilingual voice messages.** Record audio, generate an original-language transcript, translate it into the recipient's selected language, and store searchable text alongside the audio file reference. Add `message_translations` when implementing translation. Demonstrate audio playback, original text, translation, and search. [Whisper's documentation](https://github.com/openai/whisper) covers multilingual transcription and speech translation into English; other target languages need a separate translation step. |

## Shared navigation work

Use the `navigation` branch for route ownership and the local sign-in gate. Restore the selected tab and local session using Hive. Demonstrate that logging out clears the local session and protects account screens. For deep links, demonstrate opening a protected local conversation, signing in, and reaching the correct Chats tab and conversation. Run the navigation tests before merging this work.

## First-tier implementation order

1. Agree on the SQLite schema, repository contracts, and Hive box names/keys across the team.
2. Add local storage dependencies and shared initialization, database migrations, and the preferences store.
3. Implement local accounts/profile and the local session gate.
4. Implement the feed, nearby discovery, and messaging repositories and screens using local records.
5. Verify CRUD, account-specific visibility, restart persistence, and airplane-mode operation on the phone. Update [UI_GUIDE.md](UI_GUIDE.md) as screens are completed.

## Later tier: shared data and APIs

Turso `connectly1` is available for a later cloud implementation. Its standalone write/read check passed on 2026-10-19, and `connectly_connection_tests` contains `Connectly test write successful`. The PowerShell check is in `tool/test_turso_connection.ps1`; its root `dbtoken` file is ignored by Git.

When communication between real devices is introduced, define backend endpoints, authentication, shared database access, and synchronization. Replace the appropriate local repository implementations with remote implementations through app initialization. Keep cloud credentials in the backend.

Keep each new screen, its state management, and repository inside its feature folder. Review local behavior and persistence before merging a module into `main`.
