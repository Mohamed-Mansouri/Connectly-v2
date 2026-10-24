# Connectly API — ASP.NET Core / .NET 10

This is a controller-based C# Web API. Flutter calls this API; the API accesses the shared Turso database. It uses .NET 10's shared ASP.NET framework and `HttpClient`, with no Node runtime or third-party database SDK.

## Source structure

```text
Program.cs                                Service registration and HTTP middleware
Controllers/AuthController.cs             Sign up, sign in, and sign out
Controllers/MeController.cs               Current authenticated user
Controllers/HealthController.cs           Database connectivity check
Services/AuthService.cs                   Accounts, password hashes, and sessions
Authentication/SessionAuthenticationHandler.cs  Bearer authentication for [Authorize]
Data/TursoDatabase.cs                     Parameterized SQL over Turso's HTTP protocol
Models/AuthModels.cs                      Requests, responses, and application errors
migrations/001_auth.sql                   Account and session schema
```

## Run locally

From this folder:

```powershell
dotnet build
dotnet run --no-launch-profile
```

The API listens on `http://127.0.0.1:8787`. Startup applies the idempotent auth migration to Turso. `appsettings.json` contains the database URL and the path `../dbtoken`; the credential itself stays in that ignored root file.

Configuration can be overridden through .NET environment variables or user secrets:

- `Turso__DatabaseUrl`: remote libSQL database URL.
- `Turso__AuthToken`: database token, or use `Turso__TokenFile` for its file path.
- `ASPNETCORE_URLS`: listening URL.
- `AllowedHosts`: accepted API host names when deploying.

Do not place the Turso token in Flutter assets or Dart configuration.

## Routes

| Method | Route | JSON request / response |
| --- | --- | --- |
| GET | `/health` | Returns `{ "status": "ok" }` after a database query. |
| POST | `/auth/signup` | Accepts `name`, `email`, `password`; returns `user`, `token`, `expiresAt`. |
| POST | `/auth/login` | Accepts `email`, `password`; returns `user`, `token`, `expiresAt`. |
| GET | `/me` | Requires `Authorization: Bearer <user-session-token>`; returns `user`. |
| POST | `/auth/logout` | Requires the user session; revokes it and returns HTTP 204. |

Emails are trimmed and normalized to lowercase. Passwords are preserved exactly, hashed using ASP.NET Core Identity's `PasswordHasher`, and never returned. New passwords require 8–128 characters. Auth routes validate input and limit sign-up/login attempts per client IP.

Session tokens are random opaque bearer credentials, not JWTs. Only their SHA-256 hashes are stored in `auth_sessions`; sessions expire after seven days. Registration creates the user and first session in a transaction. The public user shape is `id`, `name`, `email`, `createdAt`.

Responses include `Cache-Control: no-store`. Sessions have fixed expiry with no refresh or sliding renewal; logout revokes only the supplied session. Flutter saves the token in platform secure storage and keeps the user profile in memory. Hive remembers only the optional email, independently of authentication. See the [authentication storage and cache guide](../UI_GUIDE.md#authentication-storage-and-cache) for exact keys, restoration, storage failures, and offline logout behavior.

## Test with the connected Android phone

Keep the API running, then from the repository root:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" -s ae64b3ca reverse tcp:8787 tcp:8787
flutter run -d ae64b3ca --dart-define=API_BASE_URL=http://127.0.0.1:8787
```

USB reverse connects the phone's loopback port to this PC. The Android debug build permits HTTP only for loopback hosts. Other devices need their own reverse mapping or a deployed HTTPS API. Release Flutter builds require an HTTPS `API_BASE_URL`.

Create an account in the app, open Profile to inspect the signed-in user, sign out, and sign in again. Device session tokens use platform secure storage; Hive retains the optional remembered email. Startup validates a saved token through `/me` before granting access.

## Integration check

With the API running, from the repository root:

```powershell
.\backend\tests\Test-Authentication.ps1
```

The script tests real API/database behavior using a unique generated account, including duplicate registration, incorrect credentials, password hashing, profile authorization, transaction rollback, logout revocation, and session expiry. It removes only its generated account and sessions, and never prints passwords or tokens. It uses the default Turso settings and root credential file; adapt it before testing a differently configured database.
