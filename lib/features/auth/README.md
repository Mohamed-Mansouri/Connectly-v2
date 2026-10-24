# Auth module

This branch owns the Profile tab. `module_entry.dart` connects the navigation shell to `presentation/profile_screen.dart`. The screen is an empty starting view; signup, login, profile data, and API calls are still to be built.

Planned endpoints: `POST /auth/signup`, `POST /auth/login`, `GET /me`, and `PATCH /me`. The advanced demonstration is face verification with a liveness challenge, rejection case, and password fallback. Decide how biometric data is protected before implementing it.
