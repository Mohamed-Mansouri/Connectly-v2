using System.Security.Claims;
using System.Text.Encodings.Web;
using System.Text.RegularExpressions;
using Connectly.Api.Services;
using Microsoft.AspNetCore.Authentication;
using Microsoft.Extensions.Options;

namespace Connectly.Api.Authentication;

public sealed class SessionAuthenticationHandler(
    IOptionsMonitor<AuthenticationSchemeOptions> options,
    ILoggerFactory logger,
    UrlEncoder encoder,
    AuthService auth) : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
{
    public const string SchemeName = "Session";

    protected override async Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        var header = Request.Headers.Authorization.ToString();
        if (string.IsNullOrEmpty(header)) return AuthenticateResult.NoResult();
        var match = Regex.Match(header, @"^Bearer ([A-Za-z0-9_-]{43})$");
        if (!match.Success) return AuthenticateResult.Fail("Invalid session.");
        var user = await auth.FindSessionAsync(match.Groups[1].Value, Context.RequestAborted);
        if (user is null) return AuthenticateResult.Fail("Invalid or expired session.");
        Context.Items["authUser"] = user;
        var claims = new[] {
            new Claim(ClaimTypes.NameIdentifier, user.Id),
            new Claim(ClaimTypes.Name, user.Name),
            new Claim(ClaimTypes.Email, user.Email)
        };
        return AuthenticateResult.Success(new AuthenticationTicket(
            new ClaimsPrincipal(new ClaimsIdentity(claims, SchemeName)), SchemeName));
    }

    protected override async Task HandleChallengeAsync(AuthenticationProperties properties)
    {
        Response.StatusCode = StatusCodes.Status401Unauthorized;
        await Response.WriteAsJsonAsync(new {
            error = new { code = "unauthorized", message = "Your session has expired. Please sign in again." }
        });
    }
}
