# Auth module

Authentication uses `data/sqlite_auth_repository.dart` and the phone's `connectly_local.db`. Registration, login/logout, Profile, guest navigation, and session restoration work offline. Startup adds six fictional Demo accounts; create your own account on this phone. Earlier cloud accounts are separate.

`local_passwords.dart` hashes passwords with salted PBKDF2-SHA256. SQLite holds account/session records; platform secure storage holds the local-session token under `connectly_local_auth_session`. Hive keeps only the remembered email for authentication. `AuthController` retains its repository interface, so screens need no HTTP calls. The old `auth_api.dart` remains reference code and is not constructed at runtime.

`data/profile_repository.dart` stores editable name, email, a 160-character bio, a local photo (up to 2 MB), and the account's saved location. The Profile tab chooses a gallery photo and reuses the separate location setup sheet. The current auth user refreshes after a name/email change. See [UI_GUIDE.md](../../../UI_GUIDE.md) for fields and storage lifecycle. Password recovery and the face/liveness demonstration remain planned.
