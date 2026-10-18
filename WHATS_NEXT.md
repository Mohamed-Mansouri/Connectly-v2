# Next sprint

## First: run the baseline

Install Flutter, open this repository folder, and run `flutter doctor`, `flutter pub get`, `flutter analyze`, `flutter test`, and `flutter run -d chrome`. The expected path is Home -> Open modules -> Feed, Nearby, Chats, and Profile tabs. Each feature branch changes just its tab. Give v2 a separate Android application ID before Android testing beside the original app.

## Shared backend decision

Choose one backend and database, a common user ID, token format, error response, and API base URL. Each member owns their endpoints and Flutter API client inside their module. Agree on request and response JSON before implementing cross-module flows.

| Branch | First UI and API slice | Advanced functionality to demonstrate |
| --- | --- | --- |
| `auth` | Sign up, login, profile; `POST /auth/signup`, `POST /auth/login`, `GET/PATCH /me` | Face verification with a random liveness challenge, rejection case, and password fallback. |
| `feed` | List and create posts; `GET/POST /posts`, `POST /uploads` | Personalized ranking based on content embeddings and interactions, compared with newest-first results. |
| `discovery` | Nearby map and user cards; `PUT /me/location`, `GET /users/nearby` | Live proximity matching as test users cross a radius boundary. |
| `messaging` | Conversations and group chat; `GET/POST /conversations`, `GET/POST /conversations/{id}/messages` | Voice message recording, transcription, translation, and searchable text. |
| `navigation` | Route ownership, sign-in gate, and deep-link plan | Restore the correct tab and screen from a deep link after authentication. |

Keep each new screen, its state management, and API client within its feature folder. Update [UI_GUIDE.md](UI_GUIDE.md) when a screen changes. The original design screenshots are preserved on `archive/sprint-0`; their Nearby and Chat layouts can guide the relevant module work.
