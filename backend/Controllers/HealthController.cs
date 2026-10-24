using Connectly.Api.Data;
using Microsoft.AspNetCore.Mvc;

namespace Connectly.Api.Controllers;

[ApiController]
[Route("health")]
public sealed class HealthController(TursoDatabase database) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> Get(CancellationToken ct)
    {
        await database.ExecuteAsync("SELECT 1", ct);
        return Ok(new { status = "ok" });
    }
}
