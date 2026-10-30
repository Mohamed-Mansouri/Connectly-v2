# Auth module

Authentication uses `data/sqlite_auth_repository.dart` and the phone's `connectly_local.db`. Registration, login/logout, Profile, guest navigation, and session restoration work offline. The database starts empty; create accounts on this phone. Earlier cloud accounts are separate.

`local_passwords.dart` hashes passwords with salted PBKDF2-SHA256. SQLite holds account/session records; platform secure storage holds the local-session token under `connectly_local_auth_session`. Hive keeps only the remembered email for authentication. `AuthController` retains its repository interface, so screens need no HTTP calls. The old `auth_api.dart` remains reference code and is not constructed at runtime.

See [UI_GUIDE.md](../../../UI_GUIDE.md) for fields, validation, and storage lifecycle. Profile editing, password recovery, and the face/liveness demonstration remain planned.
