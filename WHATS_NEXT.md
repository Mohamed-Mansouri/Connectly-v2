# Next sprint

## Current direction: Hive and Turso

Use **Hive on the device** for local preferences, drafts, and cached data, and **Turso `connectly1`** for shared cloud records. Each feature owns its repository so its screens can use local or remote data through the same interface.

`Flutter screen -> feature repository -> Hive / authenticated backend -> Turso`

Cloud credentials belong in the backend. The root `dbtoken` file is ignored by Git and supplies the local .NET API and standalone database connection test. Authentication is implemented; synchronization between Hive and Turso remains future work.

## Completed: authentication screens and functions

The `auth` branch now opens with `lib/features/auth/presentation/login_screen.dart`, using the existing navy/yellow palette and the Urbanist fonts from `archive/sprint-0`.

- Email and password inputs support autofill and keyboard navigation.
- Required fields and email formatting are validated before submission.
- The password visibility toggle shows and hides the entered password.
- **Remember my email** saves the email address in Hive's `auth_preferences` box when submitting or continuing as a guest. Unchecking it immediately removes the saved email. Passwords are never written to Hive.
- The layout scrolls for smaller screens and the keyboard, and uses a two-column layout on wide displays.
- **Continue as a guest** opens Feed / Nearby / Chats / Profile directly. Guest access does not create an authenticated session.
- **Create account** opens registration. Sign-in and registration call the .NET 10 API, display validation/service errors, and open the module tabs after success. Profile displays the account and provides logout.
- User session credentials are saved in platform secure storage. Startup calls the protected `/me` endpoint before restoring access. Hive's remembered email is independent of authentication.

The authentication API is implemented in C# under `backend/`, using ASP.NET Core controllers and services. It hashes passwords using Identity's password hasher and stores only hashes of expiring bearer sessions in Turso. See [backend/README.md](backend/README.md) for source layout, routes, setup, and the live integration check. [UI_GUIDE.md](UI_GUIDE.md) documents each auth view/action, source functions, exact storage keys, and startup/logout/offline behavior. The project owner confirmed authentication working on the connected phone on 2026-10-24.

## Implemented on `feed`: posts and connections

`main` has been merged into `feed`. The branch now supports text post creation/deletion, a chronological feed with Connections/Friends/Following filters, one-way follows, friend requests with recipient acceptance, and Like/Love/Celebrate/Insightful reactions. Own posts appear in every filter. Comments are deferred; uploads, post editing, persistent drafts/caches, and advanced ranking remain planned.

The .NET API enforces authorship, visibility, and one reaction per account/post. Feed/People are held in memory only; returning from People or pulling down refreshes the timeline. See [lib/features/feed/README.md](lib/features/feed/README.md) for behavior and verification. All 31 Flutter tests and the live feed integration check passed on 2026-10-24.

## Storage responsibilities

| Storage | Implemented now | Planned additions |
| --- | --- | --- |
| **Hive** | Optional remembered email in `auth_preferences` / `remembered_email`. | Theme, selected tab, nearby radius, post/message drafts, cached conversations. |
| **Platform secure storage** | User bearer token under `connectly_auth_session`. | Any future session changes need their own lifecycle and tests. |
| **Turso** | Shared users and seven-day session hashes; on `feed`, posts, follows, friendships, and reactions through the .NET API. | Profile updates, locations, conversations, group members, messages, transcript/translation metadata. |
| **App files / future media storage** | No implemented media upload/cache flow. | Images, recordings, and their references in application records. |

Agree on common user IDs, model fields, repository contracts, Hive box names/keys, and versioned cloud schema migrations. Keep secrets out of Flutter assets and source control. Session persistence is implemented separately from Hive. The user profile and tab state live in memory; broader persistent caching, invalidation, and synchronization remain planned. Startup requires a successful `/me` check to restore an account; remembered email does not grant offline authenticated access.

## Four member modules

The core and advanced features below are targets. The current implementation includes registration/login, Hive email preferences, secure session persistence/restoration, account display/logout, guest navigation, and the other module starting screens. Profile editing and advanced authentication remain planned work.

| Member | Core module to build | Advanced feature and required demonstration |
| --- | --- | --- |
| **1 — Accounts & profile** (`auth`) | Login, sign-up, logout, account display, and secure session restoration are implemented. Next: profile editing and password recovery. Turso holds accounts/sessions; Hive remembers the optional email. | **Face verification with a liveness challenge.** Enroll a face, request a random action, compare a new capture with the enrolled user, and demonstrate success, another-person rejection, still-photo rejection, and password fallback. [ML Kit face detection](https://developers.google.com/ml-kit/vision/face-detection) alone does not identify people. Scope this as a university prototype. |
| **2 — Posts & feed** (`feed`) | Text creation/listing/deletion, friends/following, requests, and reactions are implemented on `feed`. Next: post editing, images, persistent drafts/cache. Comments remain for later. | **Semantic recommendations.** Use embeddings, interactions, and freshness to rank posts. Demonstrate different feeds for two users and compare with chronological order. Decide where model processing runs before implementation. |
| **3 — Nearby discovery** (`discovery`) | Map, user cards, location/visibility settings, and radius filtering. The backend supplies shared user locations; Hive stores local display preferences. | **Live proximity matching.** Apply radius, shared-interest, and visibility rules as locations change. Demonstrate users entering and leaving the radius, with map and cards updating. |
| **4 — Group messaging** (`messaging`) | Conversations, groups, messages, and attachments shared through the backend. Hive stores drafts and optional local history caches. | **Multilingual voice messages.** Record audio, produce the original transcript and a recipient-language translation, then search text within authorized conversations. Demonstrate audio playback, both text versions, and a search result. [Whisper](https://github.com/openai/whisper) supports transcription and translation into English; other translation targets need a separate step. |

## Next implementation order

1. Add profile editing and its protected update endpoint to the .NET API.
2. Add password recovery and define its verification/delivery flow.
3. Agree on the other modules' models and API contracts, then implement their repositories, C# controllers/services, and screens.
4. Deploy the API to an HTTPS host when testing beyond the connected PC/phone setup.
5. Add caching/synchronization rules where offline access is needed, and implement the advanced feature demonstrations. Keep the documented phone auth regression checks when changing account behavior.

## Shared navigation and branch workflow

The `auth` branch owns the login screen, account/profile screens, and related state/data files. Shared app entry changes are needed to display login before the module tabs. Other feature branches replace their own module entry point. Keep navigation tests aligned with the chosen signed-out, guest, and authenticated flows.

Update [UI_GUIDE.md](UI_GUIDE.md) when screens or actions change. Review UI, data handling, and relevant tests before merging a feature into `main`. Read [BRANCHES.md](BRANCHES.md) before switching or merging branches.

## Verified cloud preparation

Turso `connectly1` was created and its standalone write/read test passed on 2026-10-19. The `connectly_connection_tests` table contains `Connectly test write successful`. To repeat that database check, run `.\tool\test_turso_connection.ps1`. The .NET authentication integration check also passed against Turso on 2026-10-24; run `.\backend\tests\Test-Authentication.ps1` with the API running to repeat it.
