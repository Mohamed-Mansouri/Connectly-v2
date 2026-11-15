# Auth module

Authentication uses `data/sqlite_auth_repository.dart` and the phone's `connectly_local.db`. Registration, login/logout, Profile, guest navigation, and session restoration work offline. Startup adds six fictional Demo accounts; create your own account on this phone. Earlier cloud accounts are separate.

`local_passwords.dart` hashes passwords with salted PBKDF2-SHA256. SQLite holds account/session records; platform secure storage holds the local-session token under `connectly_local_auth_session`. Hive keeps only the remembered email for authentication. `AuthController` retains its repository interface, so screens need no HTTP calls. The old `auth_api.dart` remains reference code and is not constructed at runtime.

`data/profile_repository.dart` stores editable name, email, a 160-character bio, a local photo (up to 2 MB), and the account's saved location. The Profile tab chooses a gallery photo and reuses the separate location setup sheet. The current auth user refreshes after a name/email change. See [UI_GUIDE.md](../../../UI_GUIDE.md) for fields and storage lifecycle. Password recovery and the face/liveness demonstration remain planned.

Fingerprint login is optional for a signed-in account with an enrolled device fingerprint. Profile enables it after a biometric check. A separate 90-day device token is kept in platform secure storage; each account on the phone can enable its own, and they are kept together as a list of `{userId, email, token}` entries. The Login screen shows the fingerprint button only when the typed email (case-insensitive) has fingerprint login on this phone, and it signs in that account. Stored emails follow profile email changes and are refreshed on each app start; expired entries are dropped. The fingerprint prompt runs before the device token is used to issue a fresh local session. Signing out keeps the fingerprint choice; turning it off in Profile revokes only that account's device token. Single-credential storage from earlier builds is migrated automatically. No password or fingerprint image is stored by Connectly. The earlier fingerprint-lock preference is cleared when upgrading, so enable the new login option once.

## Forgot password (email code)

Login → **Forgot password?** emails a 6-digit code to the account's address; entering it with a new password resets the account. Codes are stored only as hashes in `password_resets` (schema version 6), expire after 15 minutes, lock after 5 wrong tries, and can be re-requested after 60 seconds. A reset signs out every session for that account, including its fingerprint login. Accounts must use a real address to receive the code (the demo `name@g.m` accounts cannot).

Email goes through Gmail SMTP (`data/password_reset_mailer.dart`). To enable it:

1. Use a Gmail account with 2-Step Verification on, then create an App Password at https://myaccount.google.com/apppasswords.
2. Copy `email_secrets.example.json` to `email_secrets.json` (git-ignored) and fill in `SMTP_USER` and `SMTP_PASSWORD`.
3. Build with `--dart-define-from-file=email_secrets.json`, e.g. `flutter build apk --release --split-per-abi --target-platform android-arm64 --dart-define-from-file=email_secrets.json`.

Without these values the screen reports that reset email is not set up. The App Password is compiled into the APK, so use a dedicated sending account and do not distribute the build publicly.
