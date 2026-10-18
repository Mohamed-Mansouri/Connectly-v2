# Next sprint

## First: use the baseline

Flutter, Android Studio, and Android SDK are installed, and the baseline launched on a physical Android phone. Open this repository in VS Code and follow [README.md](README.md) for the exact terminal commands. The expected path is Home -> Open modules -> Feed, Nearby, Chats, and Profile tabs. Each feature branch changes just its tab. The Android application ID is `com.example.connectly_v2`.

Run `flutter test` on the `navigation` branch. As new screens are added, update the UI guide with their widgets, data states, and actions. The old combined preview and its design screenshots remain on `archive/sprint-0`.

## Shared backend decision

Choose one backend and database, a common user ID, token format, error response, and API base URL. Each member owns their endpoints and Flutter API client inside their module. Agree on request and response JSON before implementing cross-module flows.

| Branch | First UI and API slice | Advanced functionality to demonstrate |
| --- | --- | --- |
| `auth` | Sign up, login, profile; `POST /auth/signup`, `POST /auth/login`, `GET/PATCH /me` | Face verification with a random liveness challenge, rejection case, and password fallback. |
| `feed` | List and create posts; `GET/POST /posts`, `POST /uploads` | Personalized ranking based on content embeddings and interactions, compared with newest-first results. |
| `discovery` | Nearby map and user cards; `PUT /me/location`, `GET /users/nearby` | Live proximity matching as test users cross a radius boundary. |
| `messaging` | Conversations and group chat; `GET/POST /conversations`, `GET/POST /conversations/{id}/messages` | Voice message recording, transcription, translation, and searchable text. |
| `navigation` | Route ownership, sign-in gate, and deep-link plan | Restore the correct tab and screen from a deep link after authentication. |

Keep each new screen, its state management, and API client within its feature folder. Update [UI_GUIDE.md](UI_GUIDE.md) when a screen changes.
