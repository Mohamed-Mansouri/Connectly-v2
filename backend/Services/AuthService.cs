using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using Connectly.Api.Data;
using Connectly.Api.Models;
using Microsoft.AspNetCore.Identity;

namespace Connectly.Api.Services;

public sealed class AuthService(TursoDatabase database)
{
    private readonly PasswordHasher<AuthUser> _passwords = new();
    private readonly AuthUser _dummyUser = new("", "", "", "");
    private readonly string _dummyHash = new PasswordHasher<AuthUser>()
        .HashPassword(new AuthUser("", "", "", ""), Convert.ToHexString(RandomNumberGenerator.GetBytes(32)));

    public static string Timestamp(DateTimeOffset time) =>
        time.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", CultureInfo.InvariantCulture);

    public static string HashToken(string token) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(token))).ToLowerInvariant();

    private static string NormalizeEmail(string email)
    {
        var normalized = email.Trim().ToLowerInvariant();
        if (normalized.Length > 254 || !Regex.IsMatch(normalized, @"^[^\s@]+@[^\s@]+\.[^\s@]+$"))
            throw new ApiException(400, "invalid_input", "Enter a valid email address.");
        return normalized;
    }

    private static AuthUser UserFromRow(Dictionary<string, string?> row) =>
        new(row["id"]!, row["name"]!, row["email"]!, row["created_at"]!);

    private static (AuthResponse Response, SqlStatement Statement) NewSession(AuthUser user)
    {
        var token = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32))
            .TrimEnd('=').Replace('+', '-').Replace('/', '_');
        var now = DateTimeOffset.UtcNow;
        var expiry = Timestamp(now.AddDays(7));
        return (
            new AuthResponse(token, expiry, user),
            new SqlStatement(
                "INSERT INTO auth_sessions (token_hash, user_id, expires_at, created_at) VALUES (?, ?, ?, ?)",
                HashToken(token), user.Id, expiry, Timestamp(now)));
    }

    public async Task<AuthResponse> SignupAsync(SignupRequest request, CancellationToken ct)
    {
        var email = NormalizeEmail(request.Email);
        var name = request.Name.Trim();
        if (name.Length < 2 || name.Length > 80)
            throw new ApiException(400, "invalid_input", "Name must contain 2 to 80 characters.");
        var user = new AuthUser(Guid.NewGuid().ToString(), name, email, Timestamp(DateTimeOffset.UtcNow));
        var passwordHash = _passwords.HashPassword(user, request.Password);
        var session = NewSession(user);
        try
        {
            await database.BatchAsync([
                new SqlStatement("INSERT INTO users (id, email, name, password_hash, created_at) VALUES (?, ?, ?, ?, ?)",
                    user.Id, user.Email, user.Name, passwordHash, user.CreatedAt),
                session.Statement
            ], ct);
        }
        catch (TursoException error) when (error.Code.StartsWith("SQLITE_CONSTRAINT", StringComparison.Ordinal))
        {
            var existing = await database.ExecuteAsync("SELECT id FROM users WHERE email = ?", ct, email);
            if (existing.Rows.Count > 0)
                throw new ApiException(409, "email_taken", "An account already uses this email address.");
            throw;
        }
        return session.Response;
    }

    public async Task<AuthResponse> LoginAsync(LoginRequest request, CancellationToken ct)
    {
        var email = NormalizeEmail(request.Email);
        var result = await database.ExecuteAsync(
            "SELECT id, email, name, password_hash, created_at FROM users WHERE email = ?", ct, email);
        var row = result.Rows.FirstOrDefault();
        var user = row is null ? _dummyUser : UserFromRow(row);
        var verified = _passwords.VerifyHashedPassword(user, row?["password_hash"] ?? _dummyHash, request.Password);
        if (row is null || verified == PasswordVerificationResult.Failed)
            throw new ApiException(401, "invalid_credentials", "Email or password is incorrect.");
        var session = NewSession(user);
        if (verified == PasswordVerificationResult.SuccessRehashNeeded)
            await database.ExecuteAsync("UPDATE users SET password_hash = ? WHERE id = ?", ct,
                _passwords.HashPassword(user, request.Password), user.Id);
        await database.ExecuteAsync(session.Statement.Sql, ct, session.Statement.Args);
        return session.Response;
    }

    public async Task<AuthUser?> FindSessionAsync(string token, CancellationToken ct)
    {
        var result = await database.ExecuteAsync(
            "SELECT u.id, u.email, u.name, u.created_at FROM users u JOIN auth_sessions s ON s.user_id = u.id WHERE s.token_hash = ? AND s.expires_at > ?",
            ct, HashToken(token), Timestamp(DateTimeOffset.UtcNow));
        return result.Rows.Count > 0 ? UserFromRow(result.Rows[0]) : null;
    }

    public async Task LogoutAsync(string token, CancellationToken ct) =>
        await database.ExecuteAsync("DELETE FROM auth_sessions WHERE token_hash = ?", ct, HashToken(token));
}
