using Connectly.Api.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Connectly.Api.Controllers;

[ApiController]
[Authorize]
[Route("me")]
public sealed class MeController : ControllerBase
{
    [HttpGet]
    public IActionResult Get() => Ok(new { user = (AuthUser)HttpContext.Items["authUser"]! });
}
