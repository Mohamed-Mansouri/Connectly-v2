using System.ComponentModel.DataAnnotations;

namespace Connectly.Api.Models;

public sealed record LoginRequest(
    [Required, StringLength(254)] string Email,
    [Required, StringLength(128, MinimumLength = 1)] string Password);

public sealed record SignupRequest(
    [Required, StringLength(80, MinimumLength = 2)] string Name,
    [Required, StringLength(254)] string Email,
    [Required, StringLength(128, MinimumLength = 8)] string Password);

public sealed record AuthUser(string Id, string Name, string Email, string CreatedAt);
public sealed record AuthResponse(string Token, string ExpiresAt, AuthUser User);

public sealed class ApiException(int status, string code, string message) : Exception(message)
{
    public int Status { get; } = status;
    public string Code { get; } = code;
}

public sealed class TursoException(string code) : Exception("A database operation failed.")
{
    public string Code { get; } = code;
}
