using System.Threading.RateLimiting;
using Connectly.Api.Authentication;
using Connectly.Api.Data;
using Connectly.Api.Models;
using Connectly.Api.Services;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddControllers().ConfigureApiBehaviorOptions(options =>
{
    options.InvalidModelStateResponseFactory = _ => new BadRequestObjectResult(new {
        error = new { code = "invalid_input", message = "Check the required fields and their lengths." }
    });
});
builder.Services.AddHttpClient("Turso", client => client.Timeout = TimeSpan.FromSeconds(20));
builder.Services.AddSingleton<TursoDatabase>();
builder.Services.AddSingleton<AuthService>();
builder.Services.AddAuthentication(SessionAuthenticationHandler.SchemeName)
    .AddScheme<AuthenticationSchemeOptions, SessionAuthenticationHandler>(
        SessionAuthenticationHandler.SchemeName, _ => { });
builder.Services.AddAuthorization();
builder.Services.AddRateLimiter(options =>
{
    options.AddPolicy("auth", context => RateLimitPartition.GetFixedWindowLimiter(
        context.Connection.RemoteIpAddress?.ToString() ?? "unknown",
        _ => new FixedWindowRateLimiterOptions {
            PermitLimit = 30,
            Window = TimeSpan.FromMinutes(15),
            QueueLimit = 0,
            AutoReplenishment = true
        }));
    options.OnRejected = async (context, ct) =>
    {
        context.HttpContext.Response.StatusCode = StatusCodes.Status429TooManyRequests;
        await context.HttpContext.Response.WriteAsJsonAsync(new {
            error = new { code = "too_many_requests", message = "Too many attempts. Please try again later." }
        }, ct);
    };
});

var app = builder.Build();
app.Use(async (context, next) =>
{
    context.Response.Headers.CacheControl = "no-store";
    context.Response.Headers.XContentTypeOptions = "nosniff";
    try { await next(context); }
    catch (OperationCanceledException) when (context.RequestAborted.IsCancellationRequested) { }
    catch (ApiException error)
    {
        context.Response.StatusCode = error.Status;
        await context.Response.WriteAsJsonAsync(new {
            error = new { code = error.Code, message = error.Message }
        });
    }
    catch (Exception error)
    {
        // Log only the failure category, never credentials, request bodies or SQL arguments.
        app.Logger.LogWarning("Backend operation failed ({Code}).",
            error is TursoException dbError ? dbError.Code : error.GetType().Name);
        context.Response.StatusCode = StatusCodes.Status503ServiceUnavailable;
        await context.Response.WriteAsJsonAsync(new {
            error = new { code = "service_unavailable", message = "The service is unavailable. Please try again." }
        });
    }
});
app.UseRouting();
app.UseRateLimiter();
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();
app.MapFallback(() => Results.NotFound(new {
    error = new { code = "not_found", message = "This endpoint does not exist." }
}));

try
{
    await app.Services.GetRequiredService<TursoDatabase>().MigrateAsync(CancellationToken.None);
}
catch (Exception error)
{
    app.Logger.LogError("Database initialization failed ({Code}). Check the Turso URL and credential file.",
        error is TursoException dbError ? dbError.Code : error.GetType().Name);
    return;
}
await app.RunAsync();
