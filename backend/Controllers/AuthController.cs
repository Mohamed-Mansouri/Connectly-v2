using Connectly.Api.Models;
using Connectly.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;

namespace Connectly.Api.Controllers;

[ApiController]
[Route("auth")]
public sealed class AuthController(AuthService auth) : ControllerBase
{
    [HttpPost("signup")]
    [EnableRateLimiting("auth")]
    public async Task<ActionResult<AuthResponse>> Signup(SignupRequest request, CancellationToken ct) =>
        StatusCode(StatusCodes.Status201Created, await auth.SignupAsync(request, ct));

    [HttpPost("login")]
    [EnableRateLimiting("auth")]
    public async Task<ActionResult<AuthResponse>> Login(LoginRequest request, CancellationToken ct) =>
        Ok(await auth.LoginAsync(request, ct));

    [HttpPost("logout")]
    [Authorize]
    public async Task<IActionResult> Logout(CancellationToken ct)
    {
        var token = Request.Headers.Authorization.ToString()["Bearer ".Length..];
        await auth.LogoutAsync(token, ct);
        return NoContent();
    }
}
